-- Fold phone_is_whatsapp into the audited customer update RPC so disable,
-- archive, and restore do not depend on a follow-up table UPDATE that
-- authenticated clients cannot perform and that can fail after status is
-- already written.

alter table public.business_customers
  add column if not exists phone_is_whatsapp boolean not null default true;

drop function if exists public.admin_update_business_customer(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  numeric,
  numeric
);

drop function if exists public.admin_update_business_customer_v2(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  numeric,
  numeric
);

create function public.admin_update_business_customer_v2(
  p_actor_id uuid,
  p_customer_id uuid,
  p_business_name text,
  p_contact_person text,
  p_phone text,
  p_city text,
  p_area text,
  p_address text,
  p_customer_discount_percent numeric,
  p_account_status text,
  p_credit_limit numeric,
  p_outstanding_balance numeric,
  p_phone_is_whatsapp boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_role text;
  v_target_profile_role text;
  v_target_profile_active boolean;
  v_target_username text;
  v_before public.business_customers%rowtype;
  v_after public.business_customers%rowtype;
  v_effective_discount_percent numeric(5,2);
  v_phone_is_whatsapp boolean;
  v_changed_fields jsonb := '[]'::jsonb;
begin
  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = p_actor_id
    and p.active
    and not p.must_change_password
    and p.role in ('admin', 'staff');

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'STAFF_AUTH_REQUIRED';
  end if;

  select c.*
  into v_before
  from public.business_customers c
  where c.id = p_customer_id
  for update;

  if not found or v_before.profile_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_NOT_FOUND';
  end if;

  v_effective_discount_percent := coalesce(
    p_customer_discount_percent,
    v_before.discount_percent,
    0
  );
  v_phone_is_whatsapp := coalesce(
    p_phone_is_whatsapp,
    v_before.phone_is_whatsapp,
    true
  );

  select p.role, p.active, p.username
  into v_target_profile_role, v_target_profile_active, v_target_username
  from public.profiles p
  where p.id = v_before.profile_id;

  if not found or v_target_profile_role <> 'customer' then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_TARGET_REQUIRED';
  end if;

  if p_business_name is null
    or char_length(btrim(p_business_name)) = 0
    or char_length(btrim(p_business_name)) > 160
  then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_UPDATE_INVALID';
  end if;

  if p_account_status is null
    or p_account_status not in ('active', 'suspended', 'archived')
    or v_effective_discount_percent < 0
    or v_effective_discount_percent >= 100
    or (
      p_customer_discount_percent is not null
      and round(p_customer_discount_percent, 2)
        <> p_customer_discount_percent
    )
    or p_credit_limit is null
    or p_credit_limit < 0
    or p_credit_limit > 9999999999.99
    or p_outstanding_balance is null
    or p_outstanding_balance < 0
    or p_outstanding_balance > 9999999999.99
    or char_length(coalesce(p_contact_person, '')) > 160
    or char_length(coalesce(p_phone, '')) > 32
    or char_length(coalesce(p_city, '')) > 100
    or char_length(coalesce(p_area, '')) > 120
    or char_length(coalesce(p_address, '')) > 500
  then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_UPDATE_INVALID';
  end if;

  if v_before.business_name is distinct from btrim(p_business_name) then
    v_changed_fields := v_changed_fields || '"business_name"'::jsonb;
  end if;
  if v_before.contact_person is distinct from nullif(btrim(p_contact_person), '') then
    v_changed_fields := v_changed_fields || '"contact_person"'::jsonb;
  end if;
  if v_before.phone is distinct from nullif(btrim(p_phone), '') then
    v_changed_fields := v_changed_fields || '"phone"'::jsonb;
  end if;
  if v_before.phone_is_whatsapp is distinct from v_phone_is_whatsapp then
    v_changed_fields := v_changed_fields || '"phone_is_whatsapp"'::jsonb;
  end if;
  if v_before.city is distinct from nullif(btrim(p_city), '') then
    v_changed_fields := v_changed_fields || '"city"'::jsonb;
  end if;
  if v_before.area is distinct from nullif(btrim(p_area), '') then
    v_changed_fields := v_changed_fields || '"area"'::jsonb;
  end if;
  if v_before.address is distinct from nullif(btrim(p_address), '') then
    v_changed_fields := v_changed_fields || '"address"'::jsonb;
  end if;
  if v_before.discount_percent is distinct from v_effective_discount_percent then
    v_changed_fields := v_changed_fields || '"discount_percent"'::jsonb;
  end if;
  if v_before.account_status is distinct from p_account_status then
    v_changed_fields := v_changed_fields || '"account_status"'::jsonb;
  end if;
  if v_before.credit_limit is distinct from p_credit_limit then
    v_changed_fields := v_changed_fields || '"credit_limit"'::jsonb;
  end if;
  if v_before.outstanding_balance is distinct from p_outstanding_balance then
    v_changed_fields := v_changed_fields || '"outstanding_balance"'::jsonb;
  end if;

  update public.business_customers
  set
    business_name = btrim(p_business_name),
    contact_person = nullif(btrim(p_contact_person), ''),
    phone = nullif(btrim(p_phone), ''),
    phone_is_whatsapp = v_phone_is_whatsapp,
    city = nullif(btrim(p_city), ''),
    area = nullif(btrim(p_area), ''),
    address = nullif(btrim(p_address), ''),
    discount_percent = v_effective_discount_percent,
    account_status = p_account_status,
    credit_limit = p_credit_limit,
    outstanding_balance = p_outstanding_balance,
    archived_at = case
      when p_account_status = 'archived'
        then coalesce(archived_at, now())
      else null
    end
  where id = p_customer_id
    and profile_id = v_before.profile_id
  returning *
  into v_after;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_UPDATE_CONFLICT';
  end if;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    p_actor_id,
    'customer.updated',
    'business_customers',
    v_after.id,
    jsonb_build_object(
      'actor_role', v_actor_role,
      'target_profile_id', v_after.profile_id,
      'target_profile_active', v_target_profile_active,
      'changed_fields', v_changed_fields,
      'discount_percent', jsonb_build_object(
        'from', v_before.discount_percent,
        'to', v_after.discount_percent
      ),
      'account_status', jsonb_build_object(
        'from', v_before.account_status,
        'to', v_after.account_status
      ),
      'credit_limit', jsonb_build_object(
        'from', v_before.credit_limit,
        'to', v_after.credit_limit
      ),
      'outstanding_balance', jsonb_build_object(
        'from', v_before.outstanding_balance,
        'to', v_after.outstanding_balance
      ),
      'phone_is_whatsapp', jsonb_build_object(
        'from', v_before.phone_is_whatsapp,
        'to', v_after.phone_is_whatsapp
      )
    )
  );

  return to_jsonb(v_after) || jsonb_build_object(
    'profiles', jsonb_build_object(
      'username', coalesce(v_target_username, '')
    )
  );
end;
$$;

revoke all on function public.admin_update_business_customer_v2(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  numeric,
  numeric,
  boolean
) from public, anon, authenticated, service_role;
grant execute on function public.admin_update_business_customer_v2(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  numeric,
  numeric,
  boolean
) to service_role;

comment on function public.admin_update_business_customer_v2(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  numeric,
  numeric,
  boolean
) is
  'Service-only audited staff/admin customer update, including account status and WhatsApp phone preference.';

create function public.admin_update_business_customer(
  p_actor_id uuid,
  p_customer_id uuid,
  p_business_name text,
  p_contact_person text,
  p_phone text,
  p_city text,
  p_area text,
  p_address text,
  p_price_group_id uuid,
  p_account_status text,
  p_credit_limit numeric,
  p_outstanding_balance numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_discount_percent numeric(5,2);
begin
  select customer.discount_percent
  into v_discount_percent
  from public.business_customers customer
  where customer.id = p_customer_id
  for update;

  return public.admin_update_business_customer_v2(
    p_actor_id,
    p_customer_id,
    p_business_name,
    p_contact_person,
    p_phone,
    p_city,
    p_area,
    p_address,
    coalesce(v_discount_percent, 0),
    p_account_status,
    p_credit_limit,
    p_outstanding_balance,
    null
  );
end;
$$;

revoke all on function public.admin_update_business_customer(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  numeric,
  numeric
) from public, anon, authenticated, service_role;
grant execute on function public.admin_update_business_customer(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  numeric,
  numeric
) to service_role;

notify pgrst, 'reload schema';
