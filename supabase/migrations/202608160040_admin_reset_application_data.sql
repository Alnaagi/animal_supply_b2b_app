-- Privileged application-data reset for a signed-in admin Edge Function.
-- Execute is granted only to service_role. Flutter never calls this RPC.
--
-- Wiped: catalog, orders, customers, banners, inventory, invites,
-- notifications, device tokens, local sync outbox, price groups, and
-- product-image storage objects.
-- Preserved: the calling admin Auth/profile row, other admin/staff
-- profiles, app_settings, app_versions, audit_logs, edge_rate_limits.
-- Customer Auth users are deleted after their public.profiles rows.

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

  -- Keep historical audit rows; drop FK blockers before customer profile delete.
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

comment on function public.admin_reset_application_data(uuid) is
  'Admin-only application data wipe. Callable solely by service_role from admin-reset-application-data. Does not delete the calling admin Auth user.';

revoke all on function public.admin_reset_application_data(uuid)
  from public, anon, authenticated;
grant execute on function public.admin_reset_application_data(uuid)
  to service_role;
