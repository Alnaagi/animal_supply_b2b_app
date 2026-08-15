-- Read-only legacy-data diagnostics for projects that have applied the
-- additive hardening migration but have not yet validated migration 027.
-- Run this file before migration 027. The first result set must return zero
-- rows; repair every reported row before retrying `supabase db push`.

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
    jsonb_build_object(
      'outstanding_balance',
      c.outstanding_balance
    )
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
    'products_stock_nonnegative',
    p.id::text,
    jsonb_build_object(
      'sku',
      p.sku,
      'stock_quantity',
      p.stock_quantity
    )
  from public.products p
  where p.stock_quantity < 0

  union all

  select
    'products_moq_positive',
    p.id::text,
    jsonb_build_object(
      'sku',
      p.sku,
      'min_order_quantity',
      p.min_order_quantity
    )
  from public.products p
  where p.min_order_quantity <= 0

  union all

  select
    'product_prices_price_nonnegative',
    pp.id::text,
    jsonb_build_object(
      'product_id',
      pp.product_id,
      'price_group_id',
      pp.price_group_id,
      'price',
      pp.price
    )
  from public.product_prices pp
  where pp.price < 0

  union all

  select
    'customer_special_prices_price_nonnegative',
    sp.id::text,
    jsonb_build_object(
      'customer_id',
      sp.customer_id,
      'product_id',
      sp.product_id,
      'price',
      sp.price
    )
  from public.customer_special_prices sp
  where sp.price < 0

  union all

  select
    'orders_amounts_nonnegative',
    o.id::text,
    jsonb_build_object(
      'order_number',
      o.order_number,
      'subtotal',
      o.subtotal,
      'delivery_fee',
      o.delivery_fee,
      'handling_fee',
      o.handling_fee
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
      'order_id',
      oi.order_id,
      'product_id',
      oi.product_id,
      'unit_price',
      oi.unit_price
    )
  from public.order_items oi
  where oi.unit_price < 0

  union all

  select
    'app_versions_minimum_code_positive',
    v.id::text,
    jsonb_build_object(
      'platform',
      v.platform,
      'version_code',
      v.version_code,
      'minimum_supported_code',
      v.minimum_supported_code
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
      'platform',
      v.platform,
      'version_code',
      v.version_code,
      'file_size_bytes',
      v.file_size_bytes
    )
  from public.app_versions v
  where v.file_size_bytes < 0

  union all

  select
    'app_versions_sha256_format',
    v.id::text,
    jsonb_build_object(
      'platform',
      v.platform,
      'version_code',
      v.version_code,
      'sha256',
      v.sha256
    )
  from public.app_versions v
  where v.sha256 is not null
    and v.sha256 !~ '^[0-9a-fA-F]{64}$'
)
select check_name, entity_id, details
from violations
order by check_name, entity_id;

-- Before migration 027, every row below must report `exists = true`.
-- `validated = false` is expected until migration 027 succeeds.
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
    ('products', 'products_stock_nonnegative'),
    ('products', 'products_moq_positive'),
    ('product_prices', 'product_prices_price_nonnegative'),
    (
      'customer_special_prices',
      'customer_special_prices_price_nonnegative'
    ),
    ('orders', 'orders_amounts_nonnegative'),
    ('order_items', 'order_items_unit_price_nonnegative'),
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
