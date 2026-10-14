-- Read-only production diagnostics for a project after every migration through
-- 202608020032 has succeeded. The first result set must return zero rows.
-- For a push blocked by legacy constraint validation at migration 027, run
-- legacy_constraints_preflight.sql instead because this file references
-- columns and functions introduced by later migrations.

with violations as (
  select
    'business_customers_credit_limit_nonnegative'::text as check_name,
    c.id::text as entity_id,
    jsonb_build_object('credit_limit', c.credit_limit) as details
  from public.business_customers c
  where c.credit_limit < 0

  union all

  select
    'business_customers_outstanding_nonnegative',
    c.id::text,
    jsonb_build_object('outstanding_balance', c.outstanding_balance)
  from public.business_customers c
  where c.outstanding_balance < 0

  union all

  select
    'products_price_nonnegative',
    p.id::text,
    jsonb_build_object('sku', p.sku, 'base_price', p.base_price)
  from public.products p
  where p.base_price < 0

  union all

  select
    'products_retail_unit_price_positive',
    p.id::text,
    jsonb_build_object(
      'sku', p.sku,
      'retail_unit_price', p.retail_unit_price
    )
  from public.products p
  where p.retail_unit_price is not null
    and p.retail_unit_price <= 0

  union all

  select
    'active_products_retail_unit_price_missing',
    p.id::text,
    jsonb_build_object('sku', p.sku)
  from public.products p
  where p.active
    and p.archived_at is null
    and p.retail_unit_price is null

  union all

  select
    'products_units_per_box_supported_range',
    p.id::text,
    jsonb_build_object(
      'sku', p.sku,
      'units_per_box', p.units_per_box
    )
  from public.products p
  where p.units_per_box is not null
    and p.units_per_box not between 1 and 1000000

  union all

  select
    'products_stock_nonnegative',
    p.id::text,
    jsonb_build_object('sku', p.sku, 'stock_quantity', p.stock_quantity)
  from public.products p
  where p.stock_quantity < 0

  union all

  select
    'products_moq_positive',
    p.id::text,
    jsonb_build_object(
      'sku', p.sku,
      'min_order_quantity', p.min_order_quantity
    )
  from public.products p
  where p.min_order_quantity not between 1 and 1000000

  union all

  select
    'product_prices_price_nonnegative',
    pp.id::text,
    jsonb_build_object(
      'product_id', pp.product_id,
      'price_group_id', pp.price_group_id,
      'price', pp.price
    )
  from public.product_prices pp
  where pp.price < 0

  union all

  select
    'customer_special_prices_price_nonnegative',
    sp.id::text,
    jsonb_build_object(
      'customer_id', sp.customer_id,
      'product_id', sp.product_id,
      'price', sp.price
    )
  from public.customer_special_prices sp
  where sp.price < 0

  union all

  select
    'orders_amounts_nonnegative',
    o.id::text,
    jsonb_build_object(
      'order_number', o.order_number,
      'subtotal', o.subtotal,
      'delivery_fee', o.delivery_fee,
      'handling_fee', o.handling_fee
    )
  from public.orders o
  where o.subtotal < 0
    or o.delivery_fee < 0
    or o.handling_fee < 0

  union all

  select
    'order_items_unit_price_nonnegative',
    oi.id::text,
    jsonb_build_object(
      'order_id', oi.order_id,
      'product_id', oi.product_id,
      'unit_price', oi.unit_price
    )
  from public.order_items oi
  where oi.unit_price < 0

  union all

  select
    'order_items_quantity_supported_range',
    oi.id::text,
    jsonb_build_object(
      'order_id', oi.order_id,
      'quantity', oi.quantity
    )
  from public.order_items oi
  where oi.quantity not between 1 and 1000000

  union all

  select
    'order_items_units_per_box_snapshot_supported_range',
    oi.id::text,
    jsonb_build_object(
      'order_id', oi.order_id,
      'units_per_box_snapshot', oi.units_per_box_snapshot
    )
  from public.order_items oi
  where oi.units_per_box_snapshot is not null
    and oi.units_per_box_snapshot not between 1 and 1000000

  union all

  select
    'order_items_retail_unit_price_snapshot_positive',
    oi.id::text,
    jsonb_build_object(
      'order_id', oi.order_id,
      'retail_unit_price_snapshot', oi.retail_unit_price_snapshot
    )
  from public.order_items oi
  where oi.retail_unit_price_snapshot is not null
    and oi.retail_unit_price_snapshot <= 0

  union all

  select
    'app_versions_minimum_code_positive',
    v.id::text,
    jsonb_build_object(
      'platform', v.platform,
      'version_code', v.version_code,
      'minimum_supported_code', v.minimum_supported_code
    )
  from public.app_versions v
  where v.minimum_supported_code <= 0
    or v.version_code <= 0
    or v.minimum_supported_code > v.version_code

  union all

  select
    'app_versions_file_size_nonnegative',
    v.id::text,
    jsonb_build_object(
      'platform', v.platform,
      'version_code', v.version_code,
      'file_size_bytes', v.file_size_bytes
    )
  from public.app_versions v
  where v.file_size_bytes < 0

  union all

  select
    'app_versions_sha256_format',
    v.id::text,
    jsonb_build_object(
      'platform', v.platform,
      'version_code', v.version_code,
      'sha256', v.sha256
    )
  from public.app_versions v
  where v.sha256 is not null
    and v.sha256 !~ '^[0-9a-fA-F]{64}$'

  union all

  select
    'inventory_reservation_identity_mismatch',
    r.id::text,
    jsonb_build_object(
      'reservation_order_id', r.order_id,
      'reservation_order_item_id', r.order_item_id,
      'reservation_product_id', r.product_id,
      'reservation_quantity', r.quantity,
      'actual_order_id', oi.order_id,
      'actual_product_id', oi.product_id,
      'actual_quantity', oi.quantity
    )
  from public.inventory_reservations r
  left join public.order_items oi
    on oi.id = r.order_item_id
    and oi.order_id = r.order_id
    and oi.product_id = r.product_id
    and oi.quantity = r.quantity
  where oi.id is null

  union all

  select
    'order_reservation_incomplete',
    oi.id::text,
    jsonb_build_object(
      'order_id', o.id,
      'order_status', o.status,
      'product_id', oi.product_id,
      'ordered_quantity', oi.quantity,
      'active_rows', count(r.id) filter (where r.status = 'active'),
      'active_reserved_quantity',
      coalesce(
        sum(r.quantity) filter (where r.status = 'active'),
        0
      )
    )
  from public.orders o
  join public.order_items oi on oi.order_id = o.id
  left join public.inventory_reservations r
    on r.order_id = o.id
    and r.order_item_id = oi.id
    and r.product_id = oi.product_id
  where o.status in ('confirmed', 'preparing', 'ready')
  group by o.id, o.status, oi.id, oi.product_id, oi.quantity
  having count(r.id) filter (where r.status = 'active') <> 1
    or coalesce(
      sum(r.quantity) filter (where r.status = 'active'),
      0
    ) <> oi.quantity

  union all

  select
    'product_stock_below_active_reservations',
    p.id::text,
    jsonb_build_object(
      'sku', p.sku,
      'stock_quantity', p.stock_quantity,
      'active_reserved_quantity',
      coalesce(
        sum(r.quantity) filter (
          where oi.stock_tracking_enabled_snapshot
        ),
        0
      )
    )
  from public.products p
  left join public.inventory_reservations r
    on r.product_id = p.id
    and r.status = 'active'
  left join public.order_items oi
    on oi.id = r.order_item_id
    and oi.order_id = r.order_id
    and oi.product_id = r.product_id
    and oi.quantity = r.quantity
  where p.stock_tracking_enabled
  group by p.id, p.sku, p.stock_quantity
  having p.stock_quantity < coalesce(
    sum(r.quantity) filter (
      where oi.stock_tracking_enabled_snapshot
    ),
    0
  )

  union all

  select
    'untracked_product_has_active_tracked_reservations',
    p.id::text,
    jsonb_build_object(
      'sku', p.sku,
      'active_tracked_quantity',
      coalesce(
        sum(r.quantity) filter (
          where oi.stock_tracking_enabled_snapshot
        ),
        0
      )
    )
  from public.products p
  join public.inventory_reservations r
    on r.product_id = p.id
    and r.status = 'active'
  join public.order_items oi
    on oi.id = r.order_item_id
    and oi.order_id = r.order_id
    and oi.product_id = r.product_id
    and oi.quantity = r.quantity
  where not p.stock_tracking_enabled
  group by p.id, p.sku
  having coalesce(
    sum(r.quantity) filter (
      where oi.stock_tracking_enabled_snapshot
    ),
    0
  ) > 0

  union all

  select
    'active_device_token_for_locked_account',
    dt.id::text,
    jsonb_build_object(
      'profile_id', p.id,
      'role', p.role,
      'profile_active', p.active,
      'must_change_password', p.must_change_password,
      'customer_status', c.account_status,
      'customer_archived_at', c.archived_at,
      'platform', dt.platform
    )
  from public.device_tokens dt
  join public.profiles p on p.id = dt.profile_id
  left join public.business_customers c
    on c.profile_id = p.id
    and p.role = 'customer'
  where dt.active
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
    )

  union all

  select
    'unrevoked_redeemed_invite_for_unlocked_customer',
    i.id::text,
    jsonb_build_object(
      'customer_id', i.customer_id,
      'profile_id', p.id,
      'purpose', i.purpose,
      'used_at', i.used_at,
      'expires_at', i.expires_at
    )
  from public.invite_tokens i
  join public.business_customers c on c.id = i.customer_id
  join public.profiles p on p.id = c.profile_id
  where i.used_at is not null
    and i.revoked_at is null
    and i.expires_at > now()
    and not p.must_change_password

  union all

  select
    'banner_storage_policy_missing_or_unsafe',
    expected.policy_name,
    jsonb_build_object(
      'expected_command', expected.command,
      'actual_command', policy.cmd,
      'roles', policy.roles,
      'using_expression', policy.qual,
      'check_expression', policy.with_check
    )
  from (
    values
      ('banner images admin insert', 'INSERT', false, true),
      ('banner images admin update', 'UPDATE', true, true),
      ('banner images admin delete', 'DELETE', true, false),
      ('logo images admin insert', 'INSERT', false, true),
      ('logo images admin update', 'UPDATE', true, true),
      ('logo images admin delete', 'DELETE', true, false)
  ) as expected(
    policy_name,
    command,
    requires_using_expression,
    requires_check_expression
  )
  left join pg_policies policy
    on policy.schemaname = 'storage'
    and policy.tablename = 'objects'
    and policy.policyname = expected.policy_name
  cross join lateral (
    select
      lower(coalesce(policy.qual, '')) as using_expression,
      lower(coalesce(policy.with_check, '')) as check_expression
  ) expressions
  where policy.policyname is null
    or policy.cmd <> expected.command
    or policy.permissive <> 'PERMISSIVE'
    or policy.roles <> array['authenticated'::name]
    or (
      expected.requires_using_expression
      and (
        expressions.using_expression not like '%is_admin()%'
        or expressions.using_expression not like '%product-images%'
        or expressions.using_expression not like '%foldername(name)%'
        or expressions.using_expression not like '%cardinality%'
        or (
          expressions.using_expression not like '%banners%'
          and expressions.using_expression not like '%logos%'
        )
        or expressions.using_expression not like '%auth.uid()%'
        or expressions.using_expression not like '%owner_id%'
        or expressions.using_expression like '%staff%'
      )
    )
    or (
      expected.requires_check_expression
      and (
        expressions.check_expression not like '%is_admin()%'
        or expressions.check_expression not like '%product-images%'
        or expressions.check_expression not like '%foldername(name)%'
        or expressions.check_expression not like '%cardinality%'
        or (
          expressions.check_expression not like '%banners%'
          and expressions.check_expression not like '%logos%'
        )
        or expressions.check_expression not like '%auth.uid()%'
        or expressions.check_expression not like '%owner_id%'
        or expressions.check_expression like '%staff%'
      )
    )

  union all

  select
    'banner_storage_unexpected_writable_policy',
    policy.policyname,
    jsonb_build_object(
      'command', policy.cmd,
      'roles', policy.roles,
      'using_expression', policy.qual,
      'check_expression', policy.with_check
    )
  from pg_policies policy
  cross join lateral (
    select lower(
      coalesce(policy.qual, '') || ' ' || coalesce(policy.with_check, '')
    ) as expression
  ) expressions
  where policy.schemaname = 'storage'
    and policy.tablename = 'objects'
    and policy.permissive = 'PERMISSIVE'
    and policy.cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
    and policy.roles && array[
      'public'::name,
      'anon'::name,
      'authenticated'::name
    ]
    and policy.policyname not in (
      'banner images admin insert',
      'banner images admin update',
      'banner images admin delete',
      'logo images admin insert',
      'logo images admin update',
      'logo images admin delete'
    )
    and (
      expressions.expression like '%banners%'
      or (
        expressions.expression like '%product-images%'
        and expressions.expression not like '%products%'
      )
      or expressions.expression not like '%bucket_id%'
    )
)
select check_name, entity_id, details
from violations
order by check_name, entity_id;

-- After migration 031, all legacy and product-control constraints must exist
-- and report validated = true.
with expected_constraints(table_name, constraint_name) as (
  values
    (
      'business_customers',
      'business_customers_credit_limit_nonnegative'
    ),
    (
      'business_customers',
      'business_customers_outstanding_nonnegative'
    ),
    ('products', 'products_price_nonnegative'),
    ('products', 'products_retail_unit_price_positive'),
    ('products', 'products_units_per_box_positive'),
    ('products', 'products_stock_nonnegative'),
    ('products', 'products_moq_positive'),
    ('products', 'products_moq_supported_range'),
    ('product_prices', 'product_prices_price_nonnegative'),
    (
      'customer_special_prices',
      'customer_special_prices_price_nonnegative'
    ),
    ('orders', 'orders_amounts_nonnegative'),
    ('order_items', 'order_items_unit_price_nonnegative'),
    (
      'order_items',
      'order_items_units_per_box_snapshot_positive'
    ),
    (
      'order_items',
      'order_items_retail_unit_price_snapshot_positive'
    ),
    ('order_items', 'order_items_quantity_supported_range'),
    ('app_versions', 'app_versions_minimum_code_positive'),
    ('app_versions', 'app_versions_file_size_nonnegative'),
    ('app_versions', 'app_versions_sha256_format')
)
select
  expected.table_name,
  expected.constraint_name,
  constraint_row.oid is not null as exists,
  coalesce(constraint_row.convalidated, false) as validated
from expected_constraints expected
left join pg_constraint constraint_row
  on constraint_row.conname = expected.constraint_name
  and constraint_row.conrelid = to_regclass(
    'public.' || expected.table_name
  )
order by expected.table_name, expected.constraint_name;

-- Security-sensitive functions must exist as SECURITY DEFINER routines with the
-- privileged mutation paths unavailable to the authenticated client role.
with expected_security_functions(
  signature,
  authenticated_execute,
  service_role_execute
) as (
  values
    ('public.bootstrap_current_account()', true, false),
    (
      'public.complete_required_password_change_transaction(uuid)',
      false,
      true
    ),
    ('public.redeem_invite_token(text,text,uuid)', false, true),
    (
      'public.place_order_transaction(uuid,uuid,jsonb,text,text,text)',
      false,
      true
    ),
    (
      'public.place_order_transaction_impl(uuid,uuid,jsonb,text,text,text)',
      false,
      false
    ),
    (
      'public.transition_order_status_transaction(uuid,uuid,text,text)',
      false,
      true
    ),
    (
      'public.list_my_notifications(integer)',
      true,
      true
    ),
    (
      'public.unread_notification_count()',
      true,
      true
    ),
    (
      'public.mark_all_my_notifications_read()',
      true,
      true
    ),
    (
      'public.admin_update_order_pricing_transaction(uuid,uuid,jsonb,numeric,numeric)',
      false,
      true
    ),
    ('public.touch_own_last_seen()', true, false),
    (
      'public.customer_last_active_at(profiles)',
      true,
      false
    )
)
select
  expected.signature,
  function_row.oid is not null as exists,
  coalesce(function_row.prosecdef, false) as security_definer,
  coalesce(
    has_function_privilege(
      'authenticated',
      function_row.oid,
      'EXECUTE'
    ),
    false
  ) as authenticated_execute,
  coalesce(
    has_function_privilege(
      'service_role',
      function_row.oid,
      'EXECUTE'
    ),
    false
  ) as service_role_execute,
  expected.authenticated_execute as expected_authenticated_execute,
  expected.service_role_execute as expected_service_role_execute
from expected_security_functions expected
left join pg_proc function_row
  on function_row.oid = to_regprocedure(expected.signature)
order by expected.signature;

-- Both lock triggers must exist and remain enabled. Migration 028 also performs
-- an idempotent backfill, so the first result set should contain no active
-- device token owned by a locked account.
with expected_security_triggers(table_name, trigger_name) as (
  values
    ('profiles', 'deactivate_profile_tokens_on_lock'),
    ('business_customers', 'deactivate_customer_tokens_on_lock'),
    ('products', 'protect_product_stock_tracking_toggle'),
    ('orders', 'enforce_order_reservation_integrity'),
    ('products', 'enforce_reserved_stock_floor'),
    ('device_tokens', 'sync_profile_last_seen_from_device_token')
)
select
  expected.table_name,
  expected.trigger_name,
  trigger_row.oid is not null as exists,
  coalesce(trigger_row.tgenabled <> 'D', false) as enabled
from expected_security_triggers expected
left join pg_trigger trigger_row
  on trigger_row.tgrelid = to_regclass(
    'public.' || expected.table_name
  )
  and trigger_row.tgname = expected.trigger_name
  and not trigger_row.tgisinternal
order by expected.table_name, expected.trigger_name;

-- Existing objects become public catalog media through the product-images
-- bucket. Confirm none contain private or unlicensed data.
select
  o.bucket_id,
  o.name,
  o.owner_id,
  o.metadata ->> 'mimetype' as mime_type,
  o.created_at
from storage.objects o
where o.bucket_id = 'product-images'
order by o.created_at;

-- Review every permissive policy because PostgreSQL combines policies with OR.
select
  schemaname,
  tablename,
  policyname,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where
  (schemaname = 'public' and tablename in (
    'profiles',
    'business_customers',
    'customer_contacts',
    'orders',
    'order_items',
    'inventory_reservations',
    'banners',
    'product_prices',
    'customer_special_prices',
    'notifications',
    'device_tokens',
    'invite_tokens',
    'sync_outbox'
  ))
  or (schemaname = 'storage' and tablename = 'objects')
order by schemaname, tablename, policyname;
