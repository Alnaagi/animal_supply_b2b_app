\set ON_ERROR_STOP on

-- Manual authenticated-role verification for reservation-aware catalog stock.
--
-- Required psql variables:
--   customer_profile_id UUID of an active customer profile
--   product_id          UUID of an active, non-archived catalog product
--
-- Prefer a product with at least one active reservation so this proves the
-- customer sees stock minus reservations while direct reservation rows remain
-- hidden by RLS.
--
--   psql "$DATABASE_URL" \
--     -f supabase/tests/catalog_reservation_visibility.sql \
--     -v customer_profile_id=... \
--     -v product_id=...

begin;

create temporary table catalog_reservation_expectation (
  product_id uuid primary key,
  expected_available integer not null,
  active_reserved integer not null
) on commit drop;

insert into catalog_reservation_expectation (
  product_id,
  expected_available,
  active_reserved
)
select
  p.id,
  greatest(
    p.stock_quantity - coalesce(
      sum(r.quantity) filter (
        where oi.stock_tracking_enabled_snapshot
      ),
      0
    ),
    0
  )::integer,
  coalesce(
    sum(r.quantity) filter (
      where oi.stock_tracking_enabled_snapshot
    ),
    0
  )::integer
from public.products p
left join public.inventory_reservations r
  on r.product_id = p.id
  and r.status = 'active'
left join public.order_items oi
  on oi.id = r.order_item_id
  and oi.order_id = r.order_id
  and oi.product_id = r.product_id
  and oi.quantity = r.quantity
where p.id = :'product_id'::uuid
  and p.active
  and p.archived_at is null
  and p.stock_tracking_enabled
group by
  p.id,
  p.stock_quantity,
  p.hide_when_out_of_stock,
  p.min_order_quantity
having not p.hide_when_out_of_stock
  or greatest(
    p.stock_quantity - coalesce(
      sum(r.quantity) filter (
        where oi.stock_tracking_enabled_snapshot
      ),
      0
    ),
    0
  ) >= p.min_order_quantity;

do $$
begin
  if (select count(*) from catalog_reservation_expectation) <> 1 then
    raise exception
      'product_id must identify one active, non-archived product';
  end if;
  if (
    select active_reserved
    from catalog_reservation_expectation
  ) <= 0 then
    raise exception
      'product_id must have at least one active reservation for this test';
  end if;
end;
$$;

grant select on catalog_reservation_expectation to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'customer_profile_id',
  true
);

do $$
declare
  expected catalog_reservation_expectation%rowtype;
  actual_available integer;
  visible_reservation_rows integer;
begin
  select *
  into expected
  from catalog_reservation_expectation;

  select catalog.available_quantity
  into actual_available
  from public.catalog_products(expected.product_id) catalog;

  if not found then
    raise exception
      'catalog product was not visible to the supplied active customer';
  end if;

  if actual_available <> expected.expected_available then
    raise exception
      'Expected available quantity %, got % (active reserved %)',
      expected.expected_available,
      actual_available,
      expected.active_reserved;
  end if;

  select count(*)
  into visible_reservation_rows
  from public.inventory_reservations;

  if visible_reservation_rows <> 0 then
    raise exception
      'Customer role unexpectedly read % reservation rows',
      visible_reservation_rows;
  end if;
end;
$$;

rollback;
