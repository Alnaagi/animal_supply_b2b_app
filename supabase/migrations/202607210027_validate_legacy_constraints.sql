-- Fail closed if legacy rows violate constraints that were introduced as
-- NOT VALID during additive hardening. Run
-- supabase/legacy_constraints_preflight.sql to locate offending rows before
-- retrying this migration.

begin;

alter table public.business_customers
  validate constraint business_customers_credit_limit_nonnegative;
alter table public.business_customers
  validate constraint business_customers_outstanding_nonnegative;

alter table public.products
  validate constraint products_price_nonnegative;
alter table public.products
  validate constraint products_stock_nonnegative;
alter table public.products
  validate constraint products_moq_positive;

alter table public.product_prices
  validate constraint product_prices_price_nonnegative;
alter table public.customer_special_prices
  validate constraint customer_special_prices_price_nonnegative;

alter table public.orders
  validate constraint orders_amounts_nonnegative;
alter table public.order_items
  validate constraint order_items_unit_price_nonnegative;

alter table public.app_versions
  validate constraint app_versions_minimum_code_positive;
alter table public.app_versions
  validate constraint app_versions_file_size_nonnegative;
alter table public.app_versions
  validate constraint app_versions_sha256_format;

do $$
begin
  if exists (
    select 1
    from pg_constraint c
    where c.conname in (
      'business_customers_credit_limit_nonnegative',
      'business_customers_outstanding_nonnegative',
      'products_price_nonnegative',
      'products_stock_nonnegative',
      'products_moq_positive',
      'product_prices_price_nonnegative',
      'customer_special_prices_price_nonnegative',
      'orders_amounts_nonnegative',
      'order_items_unit_price_nonnegative',
      'app_versions_minimum_code_positive',
      'app_versions_file_size_nonnegative',
      'app_versions_sha256_format'
    )
      and not c.convalidated
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'LEGACY_CONSTRAINT_VALIDATION_INCOMPLETE';
  end if;
end
$$;

commit;
