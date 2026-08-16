-- Optimistic concurrency for staff writes, plus a reset mutex.
-- Flutter still uses the anon key; privileged order/customer RPCs stay
-- service_role-only and are invoked from Edge Functions.

create or replace function public.assert_fresh_updated_at(
  p_current timestamptz,
  p_expected timestamptz
)
returns void
language plpgsql
immutable
set search_path = pg_catalog
as $$
begin
  if p_expected is null then
    return;
  end if;
  if p_current is null then
    raise exception using
      errcode = 'P0001',
      message = 'STALE_WRITE';
  end if;
  if date_trunc('milliseconds', timezone('utc', p_current))
    is distinct from date_trunc('milliseconds', timezone('utc', p_expected))
  then
    raise exception using
      errcode = 'P0001',
      message = 'STALE_WRITE';
  end if;
end;
$$;

revoke all on function public.assert_fresh_updated_at(timestamptz, timestamptz)
  from public, anon, authenticated, service_role;

alter function public.transition_order_status_transaction(
  uuid,
  uuid,
  text,
  text
) rename to transition_order_status_transaction_unguarded;

create function public.transition_order_status_transaction(
  p_actor_id uuid,
  p_order_id uuid,
  p_status text,
  p_note text default null,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_order public.orders%rowtype;
begin
  select o.*
  into current_order
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_NOT_FOUND';
  end if;

  if current_order.status is distinct from p_status then
    perform public.assert_fresh_updated_at(
      current_order.updated_at,
      p_expected_updated_at
    );
  end if;

  return public.transition_order_status_transaction_unguarded(
    p_actor_id,
    p_order_id,
    p_status,
    p_note
  );
end;
$$;

comment on function public.transition_order_status_transaction(
  uuid,
  uuid,
  text,
  text,
  timestamptz
) is
  'Staff/admin order status change with optional updated_at conflict check.';

revoke all on function public.transition_order_status_transaction_unguarded(
  uuid,
  uuid,
  text,
  text
) from public, anon, authenticated, service_role;

revoke all on function public.transition_order_status_transaction(
  uuid,
  uuid,
  text,
  text,
  timestamptz
) from public, anon, authenticated;

grant execute on function public.transition_order_status_transaction(
  uuid,
  uuid,
  text,
  text,
  timestamptz
) to service_role;

alter function public.admin_update_order_pricing_transaction(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric
) rename to admin_update_order_pricing_transaction_unguarded;

create function public.admin_update_order_pricing_transaction(
  p_actor_id uuid,
  p_order_id uuid,
  p_items jsonb,
  p_delivery_fee numeric,
  p_discount_amount numeric,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_updated timestamptz;
begin
  select o.updated_at
  into current_updated
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_NOT_FOUND';
  end if;

  perform public.assert_fresh_updated_at(
    current_updated,
    p_expected_updated_at
  );

  return public.admin_update_order_pricing_transaction_unguarded(
    p_actor_id,
    p_order_id,
    p_items,
    p_delivery_fee,
    p_discount_amount
  );
end;
$$;

comment on function public.admin_update_order_pricing_transaction(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric,
  timestamptz
) is
  'Staff/admin order pricing update with optional updated_at conflict check.';

revoke all on function public.admin_update_order_pricing_transaction_unguarded(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric
) from public, anon, authenticated, service_role;

revoke all on function public.admin_update_order_pricing_transaction(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric,
  timestamptz
) from public, anon, authenticated;

grant execute on function public.admin_update_order_pricing_transaction(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric,
  timestamptz
) to service_role;

alter function public.admin_update_business_customer_v2(
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
) rename to admin_update_business_customer_v2_unguarded;

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
  p_phone_is_whatsapp boolean default null,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_updated timestamptz;
begin
  select c.updated_at
  into current_updated
  from public.business_customers c
  where c.id = p_customer_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_NOT_FOUND';
  end if;

  perform public.assert_fresh_updated_at(
    current_updated,
    p_expected_updated_at
  );

  return public.admin_update_business_customer_v2_unguarded(
    p_actor_id,
    p_customer_id,
    p_business_name,
    p_contact_person,
    p_phone,
    p_city,
    p_area,
    p_address,
    p_customer_discount_percent,
    p_account_status,
    p_credit_limit,
    p_outstanding_balance,
    p_phone_is_whatsapp
  );
end;
$$;

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
  boolean,
  timestamptz
) is
  'Service-only audited customer update with optional updated_at conflict check.';

revoke all on function public.admin_update_business_customer_v2_unguarded(
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
  boolean,
  timestamptz
) from public, anon, authenticated;

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
  boolean,
  timestamptz
) to service_role;

create or replace function public.admin_save_app_settings(
  p_settings jsonb,
  p_expected_updated_at timestamptz default null
)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_max timestamptz;
  setting_key text;
  setting_value text;
begin
  if not public.is_staff_or_admin() then
    raise exception using
      errcode = 'P0001',
      message = 'STAFF_AUTH_REQUIRED';
  end if;

  if jsonb_typeof(p_settings) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'SETTINGS_INVALID';
  end if;

  lock table public.app_settings in exclusive mode;

  select max(s.updated_at)
  into current_max
  from public.app_settings s;

  perform public.assert_fresh_updated_at(
    current_max,
    p_expected_updated_at
  );

  for setting_key, setting_value in
    select kv.key, kv.value
    from jsonb_each_text(p_settings) as kv(key, value)
  loop
    if char_length(setting_key) = 0 or char_length(setting_key) > 80 then
      raise exception using
        errcode = 'P0001',
        message = 'SETTINGS_INVALID';
    end if;
    insert into public.app_settings as settings (key, value)
    values (setting_key, coalesce(setting_value, ''))
    on conflict (key) do update
      set value = excluded.value;
  end loop;

  select max(s.updated_at)
  into current_max
  from public.app_settings s;
  return current_max;
end;
$$;

comment on function public.admin_save_app_settings(jsonb, timestamptz) is
  'Staff/admin shop settings upsert with optional generation conflict check.';

revoke all on function public.admin_save_app_settings(jsonb, timestamptz)
  from public, anon;
grant execute on function public.admin_save_app_settings(jsonb, timestamptz)
  to authenticated;

create or replace function public.admin_reset_application_data(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_role text;
  actor_active boolean;
  customer_ids uuid[] := '{}';
  deleted_customer_profiles integer := 0;
  deleted_storage_objects integer := 0;
begin
  if p_actor_id is null then
    raise exception 'ACTOR_REQUIRED';
  end if;

  if not pg_try_advisory_xact_lock(87201616) then
    raise exception using
      errcode = 'P0001',
      message = 'RESET_IN_PROGRESS';
  end if;

  select p.role, p.active
    into actor_role, actor_active
  from public.profiles p
  where p.id = p_actor_id;

  if actor_role is distinct from 'admin' or actor_active is not true then
    raise exception 'FORBIDDEN';
  end if;

  select coalesce(array_agg(p.id), '{}')
    into customer_ids
  from public.profiles p
  where p.role = 'customer'
    and p.id <> p_actor_id;

  update public.audit_logs
  set actor_id = null
  where actor_id = any (customer_ids);

  truncate table
    public.notification_deliveries,
    public.notification_outbox,
    public.notifications,
    public.notification_campaigns,
    public.inventory_reservations,
    public.order_status_history,
    public.order_items,
    public.inventory_movements,
    public.orders,
    public.product_images,
    public.product_prices,
    public.customer_special_prices,
    public.products,
    public.categories,
    public.banners,
    public.invite_tokens,
    public.customer_contacts,
    public.business_customers,
    public.device_tokens,
    public.admin_device_tokens,
    public.sync_outbox,
    public.price_groups
  restart identity;

  if to_regclass('public.order_number_seq') is not null then
    perform pg_catalog.setval('public.order_number_seq', 1, false);
  end if;

  begin
    delete from storage.objects
    where bucket_id = 'product-images';
    get diagnostics deleted_storage_objects = row_count;
  exception
    when insufficient_privilege or undefined_table then
      deleted_storage_objects := 0;
  end;

  delete from public.profiles
  where role = 'customer'
    and id <> p_actor_id;
  get diagnostics deleted_customer_profiles = row_count;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    p_actor_id,
    'application_data.reset',
    'profiles',
    p_actor_id,
    jsonb_build_object(
      'customer_profile_ids', to_jsonb(customer_ids),
      'customer_profiles_deleted', deleted_customer_profiles,
      'storage_objects_deleted', deleted_storage_objects,
      'preserved_admin_id', p_actor_id
    )
  );

  return jsonb_build_object(
    'reset', true,
    'preserved_admin_id', p_actor_id,
    'customer_user_ids', to_jsonb(customer_ids),
    'customer_profiles_deleted', deleted_customer_profiles,
    'storage_objects_deleted', deleted_storage_objects,
    'truncated_tables', jsonb_build_array(
      'notification_deliveries',
      'notification_outbox',
      'notifications',
      'notification_campaigns',
      'inventory_reservations',
      'order_status_history',
      'order_items',
      'inventory_movements',
      'orders',
      'product_images',
      'product_prices',
      'customer_special_prices',
      'products',
      'categories',
      'banners',
      'invite_tokens',
      'customer_contacts',
      'business_customers',
      'device_tokens',
      'admin_device_tokens',
      'sync_outbox',
      'price_groups'
    ),
    'preserved_tables', jsonb_build_array(
      'profiles',
      'app_settings',
      'app_versions',
      'audit_logs',
      'edge_rate_limits'
    )
  );
end;
$$;

revoke all on function public.admin_reset_application_data(uuid)
  from public, anon, authenticated;
grant execute on function public.admin_reset_application_data(uuid)
  to service_role;

notify pgrst, 'reload schema';
