-- Require a redeemed, unexpired invite before a customer can complete a
-- forced password change, minimize pre-activation client reads, and revoke
-- push access whenever an account is locked.

create or replace function public.bootstrap_current_account()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles%rowtype;
  v_customer public.business_customers%rowtype;
  v_price_group_name text;
  v_can_use_app boolean := false;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;

  select p.*
  into v_profile
  from public.profiles p
  where p.id = auth.uid();

  if not found then
    raise exception using errcode = 'P0001', message = 'PROFILE_REQUIRED';
  end if;

  if v_profile.role not in ('admin', 'staff', 'customer') then
    raise exception using errcode = 'P0001', message = 'ROLE_INVALID';
  end if;

  if v_profile.role = 'customer' then
    select c.*
    into v_customer
    from public.business_customers c
    where c.profile_id = v_profile.id;

    if found and v_customer.price_group_id is not null then
      select pg.name
      into v_price_group_name
      from public.price_groups pg
      where pg.id = v_customer.price_group_id;
    end if;
  end if;

  v_can_use_app :=
    v_profile.active
    and not v_profile.must_change_password
    and (
      v_profile.role in ('admin', 'staff')
      or (
        v_profile.role = 'customer'
        and v_customer.id is not null
        and v_customer.account_status = 'active'
        and v_customer.archived_at is null
      )
    );

  return jsonb_strip_nulls(
    jsonb_build_object(
      'id', v_profile.id,
      'username', v_profile.username,
      'role', v_profile.role,
      'active', v_profile.active,
      'must_change_password', v_profile.must_change_password,
      'full_name', case when v_can_use_app then v_profile.full_name end,
      'phone', case when v_can_use_app then v_profile.phone end,
      'customer', case
        when v_profile.role <> 'customer' or v_customer.id is null then null
        else jsonb_strip_nulls(
          jsonb_build_object(
            'id', v_customer.id,
            'account_status', v_customer.account_status,
            'business_name',
              case when v_can_use_app then v_customer.business_name end,
            'contact_person',
              case when v_can_use_app then v_customer.contact_person end,
            'phone', case when v_can_use_app then v_customer.phone end,
            'city', case when v_can_use_app then v_customer.city end,
            'area', case when v_can_use_app then v_customer.area end,
            'address', case when v_can_use_app then v_customer.address end,
            'credit_limit',
              case when v_can_use_app then v_customer.credit_limit end,
            'outstanding_balance',
              case when v_can_use_app then v_customer.outstanding_balance end,
            'price_group',
              case when v_can_use_app then v_price_group_name end
          )
        )
      end
    )
  );
end;
$$;

revoke all on function public.bootstrap_current_account()
  from public, anon, authenticated;
grant execute on function public.bootstrap_current_account()
  to authenticated;

drop policy if exists "customers own or staff"
  on public.business_customers;
create policy "customers own or staff"
on public.business_customers
for select
using (
  (
    profile_id = auth.uid()
    and public.is_active_actor()
  )
  or public.is_staff_or_admin()
);

drop policy if exists "contacts own or staff"
  on public.customer_contacts;
create policy "contacts own or staff"
on public.customer_contacts
for select
using (
  public.is_staff_or_admin()
  or (
    public.is_active_actor()
    and exists (
      select 1
      from public.business_customers c
      where c.id = customer_id
        and c.profile_id = auth.uid()
    )
  )
);

create or replace function public.complete_required_password_change_transaction(
  p_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles%rowtype;
  v_customer public.business_customers%rowtype;
  v_invite public.invite_tokens%rowtype;
begin
  if p_profile_id is null then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;

  select p.*
  into v_profile
  from public.profiles p
  where p.id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'PROFILE_REQUIRED';
  end if;

  if not v_profile.active then
    raise exception using errcode = 'P0001', message = 'PROFILE_INACTIVE';
  end if;

  if v_profile.role not in ('admin', 'staff', 'customer') then
    raise exception using errcode = 'P0001', message = 'ROLE_INVALID';
  end if;

  if not v_profile.must_change_password then
    return jsonb_build_object(
      'completed', true,
      'already_completed', true,
      'profile_id', v_profile.id
    );
  end if;

  if v_profile.role = 'customer' then
    select c.*
    into v_customer
    from public.business_customers c
    where c.profile_id = v_profile.id
      and c.account_status = 'active'
      and c.archived_at is null
    for update;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'CUSTOMER_ACCOUNT_INACTIVE';
    end if;

    select i.*
    into v_invite
    from public.invite_tokens i
    where i.customer_id = v_customer.id
      and i.purpose in ('activation', 'password_reset')
      and i.used_at is not null
      and i.used_by = v_profile.id
      and i.revoked_at is null
      and i.expires_at > now()
    order by i.used_at desc, i.created_at desc
    limit 1
    for update;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'INVITE_REDEMPTION_REQUIRED';
    end if;
  end if;

  update public.profiles
  set
    must_change_password = false,
    updated_at = now()
  where id = v_profile.id
    and must_change_password;

  if v_profile.role = 'customer' then
    update public.invite_tokens
    set
      revoked_at = coalesce(revoked_at, now()),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'password_change_completed_at', now(),
        'completion_profile_id', v_profile.id
      )
    where id = v_invite.id;

    update public.invite_tokens
    set revoked_at = now()
    where customer_id = v_customer.id
      and id <> v_invite.id
      and revoked_at is null;
  end if;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    v_profile.id,
    'profile.password_change_completed',
    'profiles',
    v_profile.id,
    jsonb_build_object(
      'role', v_profile.role,
      'invite_id', case
        when v_profile.role = 'customer' then v_invite.id
        else null
      end,
      'invite_purpose', case
        when v_profile.role = 'customer' then v_invite.purpose
        else null
      end
    )
  );

  return jsonb_build_object(
    'completed', true,
    'already_completed', false,
    'profile_id', v_profile.id,
    'invite_id', case
      when v_profile.role = 'customer' then v_invite.id
      else null
    end
  );
end;
$$;

revoke all on function public.complete_required_password_change_transaction(
  uuid
) from public, anon, authenticated;
grant execute on function public.complete_required_password_change_transaction(
  uuid
) to service_role;

create or replace function public.redeem_invite_token(
  p_token_hash text,
  p_client_code text default null,
  p_redeemed_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  invite public.invite_tokens%rowtype;
  customer public.business_customers%rowtype;
  profile public.profiles%rowtype;
  already_redeemed boolean := false;
begin
  if p_token_hash is null or length(p_token_hash) <> 64 then
    raise exception using errcode = 'P0001', message = 'INVALID_INVITE_TOKEN';
  end if;

  if p_redeemed_by is null then
    raise exception using errcode = 'P0001', message = 'INVITE_USER_MISMATCH';
  end if;

  select i.*
  into invite
  from public.invite_tokens i
  where i.token_hash = lower(p_token_hash)
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVALID_INVITE_TOKEN';
  end if;

  if invite.revoked_at is not null then
    raise exception using errcode = 'P0001', message = 'INVITE_REVOKED';
  end if;

  if invite.expires_at <= now() then
    raise exception using errcode = 'P0001', message = 'INVITE_EXPIRED';
  end if;

  select c.*
  into customer
  from public.business_customers c
  where c.id = invite.customer_id;

  if not found or customer.profile_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'INVITE_CUSTOMER_NOT_FOUND';
  end if;

  select p.*
  into profile
  from public.profiles p
  where p.id = customer.profile_id
    and p.role = 'customer';

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'INVITE_CUSTOMER_NOT_FOUND';
  end if;

  if not profile.active
    or not profile.must_change_password
    or customer.account_status <> 'active'
    or customer.archived_at is not null
  then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_ACCOUNT_INACTIVE';
  end if;

  if nullif(trim(p_client_code), '') is not null
    and lower(trim(p_client_code)) <>
      lower(coalesce(invite.client_code, profile.username, ''))
  then
    raise exception using
      errcode = 'P0001',
      message = 'INVITE_CLIENT_CODE_MISMATCH';
  end if;

  if p_redeemed_by <> profile.id then
    raise exception using errcode = 'P0001', message = 'INVITE_USER_MISMATCH';
  end if;

  if invite.used_at is not null then
    if invite.used_by is distinct from p_redeemed_by then
      raise exception using
        errcode = 'P0001',
        message = 'INVITE_ALREADY_USED';
    end if;
    already_redeemed := true;
  else
    update public.invite_tokens
    set
      used_at = now(),
      used_by = p_redeemed_by
    where id = invite.id;

    insert into public.audit_logs (
      actor_id,
      action,
      entity_table,
      entity_id,
      metadata
    )
    values (
      p_redeemed_by,
      'invite.redeemed',
      'business_customers',
      customer.id,
      jsonb_build_object(
        'invite_id', invite.id,
        'purpose', invite.purpose
      )
    );
  end if;

  return jsonb_build_object(
    'purpose', invite.purpose,
    'client_code', coalesce(invite.client_code, profile.username),
    'business_name', customer.business_name,
    'must_change_password', profile.must_change_password,
    'expires_at', invite.expires_at,
    'already_redeemed', already_redeemed
  );
end;
$$;

revoke all on function public.redeem_invite_token(text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.redeem_invite_token(text, text, uuid)
  to service_role;

create or replace function public.deactivate_profile_tokens_on_lock()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if (
    new.active is false
    or new.must_change_password is true
  ) and (
    old.active is distinct from new.active
    or old.must_change_password is distinct from new.must_change_password
  ) then
    update public.device_tokens
    set
      active = false,
      updated_at = now()
    where profile_id = new.id
      and active;
  end if;
  return new;
end;
$$;

drop trigger if exists deactivate_profile_tokens_on_lock
  on public.profiles;
create trigger deactivate_profile_tokens_on_lock
after update of active, must_change_password on public.profiles
for each row
execute function public.deactivate_profile_tokens_on_lock();

create or replace function public.deactivate_customer_tokens_on_lock()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.profile_id is not null
    and (
      new.account_status <> 'active'
      or new.archived_at is not null
    )
    and (
      old.account_status is distinct from new.account_status
      or old.archived_at is distinct from new.archived_at
    )
  then
    update public.device_tokens
    set
      active = false,
      updated_at = now()
    where profile_id = new.profile_id
      and active;
  end if;
  return new;
end;
$$;

drop trigger if exists deactivate_customer_tokens_on_lock
  on public.business_customers;
create trigger deactivate_customer_tokens_on_lock
after update of account_status, archived_at on public.business_customers
for each row
execute function public.deactivate_customer_tokens_on_lock();

-- Establish the same invariant for rows that were already locked before these
-- triggers existed. The update is idempotent and touches only active tokens
-- whose owning account is not currently allowed to use the application.
update public.device_tokens dt
set
  active = false,
  updated_at = now()
from public.profiles p
left join public.business_customers c
  on c.profile_id = p.id
  and p.role = 'customer'
where dt.profile_id = p.id
  and dt.active
  and (
    not p.active
    or p.must_change_password
    or (
      p.role = 'customer'
      and (
        c.id is null
        or c.account_status <> 'active'
        or c.archived_at is not null
      )
    )
  );

notify pgrst, 'reload schema';
