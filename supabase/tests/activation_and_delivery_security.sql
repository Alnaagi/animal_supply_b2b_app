\set ON_ERROR_STOP on

-- Rollback-only verification for migration 202607220028.
--
-- Required psql variable:
--   customer_profile_id UUID of an active customer profile whose linked
--                       business customer is active and not archived.
--
-- Run this against a local or staging Supabase database, not the live project:
--
--   psql "$DATABASE_URL" \
--     -f supabase/tests/activation_and_delivery_security.sql \
--     -v customer_profile_id=...
--
-- The script temporarily locks the supplied account, creates synthetic invite,
-- contact, and device-token rows, verifies the security boundaries, and rolls
-- the entire transaction back.

begin;

create temporary table activation_security_context (
  profile_id uuid primary key,
  customer_id uuid not null,
  contact_id uuid,
  valid_invite_id uuid,
  expired_invite_id uuid,
  unredeemed_invite_id uuid,
  profile_lock_token_id uuid,
  customer_lock_token_id uuid
) on commit drop;

insert into activation_security_context (profile_id, customer_id)
select p.id, c.id
from public.profiles p
join public.business_customers c on c.profile_id = p.id
where p.id = :'customer_profile_id'::uuid
  and p.role = 'customer'
  and p.active
  and not p.must_change_password
  and c.account_status = 'active'
  and c.archived_at is null;

do $$
begin
  if (select count(*) from activation_security_context) <> 1 then
    raise exception
      'customer_profile_id must identify one active, unlocked customer';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.complete_required_password_change_transaction(uuid)',
    'EXECUTE'
  ) then
    raise exception
      'authenticated unexpectedly executes password completion transaction';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.complete_required_password_change_transaction(uuid)',
    'EXECUTE'
  ) then
    raise exception
      'service_role cannot execute password completion transaction';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.redeem_invite_token(text,text,uuid)',
    'EXECUTE'
  ) then
    raise exception 'authenticated unexpectedly executes invite redemption RPC';
  end if;
end;
$$;

do $$
declare
  test activation_security_context%rowtype;
  inserted_contact_id uuid;
  inserted_token_id uuid;
begin
  select * into test from activation_security_context;

  insert into public.customer_contacts (
    customer_id,
    name,
    phone,
    role_title
  )
  values (
    test.customer_id,
    'جهة اتصال لاختبار الأمان',
    '0910000000',
    'اختبار'
  )
  returning id into inserted_contact_id;

  insert into public.device_tokens (
    profile_id,
    token,
    platform,
    device_id,
    device_label
  )
  values (
    test.profile_id,
    'activation-security-profile-' || gen_random_uuid()::text,
    'web',
    'activation-security-profile-lock',
    'Migration 028 profile lock test'
  )
  returning id into inserted_token_id;

  update activation_security_context
  set
    contact_id = inserted_contact_id,
    profile_lock_token_id = inserted_token_id
  where profile_id = test.profile_id;

  -- Existing valid invites would make the missing-proof assertion ambiguous.
  -- This update remains transaction-local and is rolled back at the end.
  update public.invite_tokens
  set revoked_at = coalesce(revoked_at, now())
  where customer_id = test.customer_id
    and revoked_at is null;
end;
$$;

grant select on activation_security_context to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'customer_profile_id',
  true
);

do $$
declare
  test activation_security_context%rowtype;
begin
  select * into test from activation_security_context;

  if (
    select count(*)
    from public.business_customers c
    where c.id = test.customer_id
  ) <> 1 then
    raise exception 'Active customer cannot read its own customer row';
  end if;

  if (
    select count(*)
    from public.customer_contacts cc
    where cc.id = test.contact_id
  ) <> 1 then
    raise exception 'Active customer cannot read its own contact row';
  end if;
end;
$$;

reset role;

update public.profiles
set must_change_password = true
where id = :'customer_profile_id'::uuid;

do $$
declare
  test activation_security_context%rowtype;
begin
  select * into test from activation_security_context;

  if exists (
    select 1
    from public.device_tokens dt
    where dt.id = test.profile_lock_token_id
      and dt.active
  ) then
    raise exception 'Profile lock did not deactivate its device token';
  end if;
end;
$$;

do $$
declare
  test activation_security_context%rowtype;
  inserted_expired_id uuid;
  inserted_unredeemed_id uuid;
begin
  select * into test from activation_security_context;

  insert into public.invite_tokens (
    customer_id,
    token_hash,
    client_code,
    purpose,
    expires_at,
    used_at,
    used_by
  )
  values (
    test.customer_id,
    encode(
      digest(
        'activation-security-expired-' || gen_random_uuid()::text,
        'sha256'
      ),
      'hex'
    ),
    'security-test',
    'activation',
    now() - interval '1 hour',
    now() - interval '2 hours',
    test.profile_id
  )
  returning id into inserted_expired_id;

  insert into public.invite_tokens (
    customer_id,
    token_hash,
    client_code,
    purpose,
    expires_at
  )
  values (
    test.customer_id,
    encode(
      digest(
        'activation-security-unredeemed-' || gen_random_uuid()::text,
        'sha256'
      ),
      'hex'
    ),
    'security-test',
    'password_reset',
    now() + interval '1 hour'
  )
  returning id into inserted_unredeemed_id;

  update activation_security_context
  set
    expired_invite_id = inserted_expired_id,
    unredeemed_invite_id = inserted_unredeemed_id
  where profile_id = test.profile_id;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'customer_profile_id',
  true
);

do $$
declare
  test activation_security_context%rowtype;
  bootstrap jsonb;
begin
  select * into test from activation_security_context;

  if exists (
    select 1
    from public.business_customers c
    where c.id = test.customer_id
  ) then
    raise exception
      'Password-change-required customer read its protected customer row';
  end if;

  if exists (
    select 1
    from public.customer_contacts cc
    where cc.id = test.contact_id
  ) then
    raise exception
      'Password-change-required customer read its protected contact row';
  end if;

  select public.bootstrap_current_account() into bootstrap;
  if bootstrap->>'must_change_password' <> 'true' then
    raise exception 'Bootstrap omitted the forced password-change flag';
  end if;
  if bootstrap ? 'full_name' or bootstrap ? 'phone' then
    raise exception 'Locked bootstrap exposed protected profile details';
  end if;
  if coalesce(bootstrap->'customer', '{}'::jsonb) ? 'business_name' then
    raise exception 'Locked bootstrap exposed protected customer details';
  end if;
end;
$$;

reset role;

do $$
declare
  test activation_security_context%rowtype;
  error_message text;
begin
  select * into test from activation_security_context;

  begin
    perform public.complete_required_password_change_transaction(
      test.profile_id
    );
    raise exception 'Expected INVITE_REDEMPTION_REQUIRED';
  exception
    when sqlstate 'P0001' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'INVITE_REDEMPTION_REQUIRED' then
        raise exception
          'Expected INVITE_REDEMPTION_REQUIRED, got %',
          error_message;
      end if;
  end;

  if not (
    select p.must_change_password
    from public.profiles p
    where p.id = test.profile_id
  ) then
    raise exception 'Failed invite gate unexpectedly unlocked the profile';
  end if;
end;
$$;

do $$
declare
  test activation_security_context%rowtype;
  inserted_valid_id uuid;
  completion jsonb;
  repeated_completion jsonb;
begin
  select * into test from activation_security_context;

  insert into public.invite_tokens (
    customer_id,
    token_hash,
    client_code,
    purpose,
    expires_at,
    used_at,
    used_by
  )
  values (
    test.customer_id,
    encode(
      digest(
        'activation-security-valid-' || gen_random_uuid()::text,
        'sha256'
      ),
      'hex'
    ),
    'security-test',
    'password_reset',
    now() + interval '1 hour',
    now(),
    test.profile_id
  )
  returning id into inserted_valid_id;

  update activation_security_context
  set valid_invite_id = inserted_valid_id
  where profile_id = test.profile_id;

  completion := public.complete_required_password_change_transaction(
    test.profile_id
  );
  if coalesce((completion->>'completed')::boolean, false) is not true
    or coalesce((completion->>'already_completed')::boolean, true) is not false
  then
    raise exception 'Valid invite did not complete the password-change gate';
  end if;

  if (
    select p.must_change_password
    from public.profiles p
    where p.id = test.profile_id
  ) then
    raise exception 'Valid invite did not unlock the profile';
  end if;

  if exists (
    select 1
    from public.invite_tokens i
    where i.id in (
      inserted_valid_id,
      test.expired_invite_id,
      test.unredeemed_invite_id
    )
      and i.revoked_at is null
  ) then
    raise exception 'Password completion left a customer invite unrevoked';
  end if;

  repeated_completion :=
    public.complete_required_password_change_transaction(test.profile_id);
  if coalesce(
    (repeated_completion->>'already_completed')::boolean,
    false
  ) is not true then
    raise exception 'Repeated password completion was not idempotent';
  end if;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'customer_profile_id',
  true
);

do $$
declare
  test activation_security_context%rowtype;
begin
  select * into test from activation_security_context;

  if (
    select count(*)
    from public.business_customers c
    where c.id = test.customer_id
  ) <> 1 then
    raise exception 'Completed customer did not regain owner-row access';
  end if;
end;
$$;

reset role;

do $$
declare
  test activation_security_context%rowtype;
  inserted_token_id uuid;
begin
  select * into test from activation_security_context;

  insert into public.device_tokens (
    profile_id,
    token,
    platform,
    device_id,
    device_label
  )
  values (
    test.profile_id,
    'activation-security-customer-' || gen_random_uuid()::text,
    'android',
    'activation-security-customer-lock',
    'Migration 028 customer lock test'
  )
  returning id into inserted_token_id;

  update activation_security_context
  set customer_lock_token_id = inserted_token_id
  where profile_id = test.profile_id;

  update public.business_customers
  set account_status = 'suspended'
  where id = test.customer_id;

  if exists (
    select 1
    from public.device_tokens dt
    where dt.id = inserted_token_id
      and dt.active
  ) then
    raise exception 'Customer suspension did not deactivate its device token';
  end if;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'customer_profile_id',
  true
);

do $$
declare
  test activation_security_context%rowtype;
begin
  select * into test from activation_security_context;

  if exists (
    select 1
    from public.business_customers c
    where c.id = test.customer_id
  ) then
    raise exception 'Suspended customer retained owner-row access';
  end if;
end;
$$;

reset role;
rollback;
