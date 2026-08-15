-- Keep dashboard and operational-report totals authoritative and bounded.
-- These functions bypass table RLS only after an explicit active staff/admin
-- role check, then return read-only aggregate JSON to Flutter.

create index if not exists idx_orders_created_at
  on public.orders(created_at desc);

create or replace function public.admin_dashboard_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  actor_role text;
  result jsonb;
begin
  actor_role := public.current_role();
  if actor_role is null or actor_role not in ('admin', 'staff') then
    raise exception 'STAFF_OR_ADMIN_REQUIRED'
      using errcode = '42501';
  end if;

  with available_products as (
    select
      p.id,
      p.name,
      p.sku,
      greatest(
        p.stock_quantity - coalesce(
          sum(r.quantity) filter (where r.status = 'active'),
          0
        ),
        0
      )::integer as available_quantity
    from public.products p
    left join public.inventory_reservations r
      on r.product_id = p.id
      and r.status = 'active'
    where p.active
      and p.archived_at is null
    group by p.id, p.name, p.sku, p.stock_quantity
  ),
  pending_rows as (
    select
      o.id,
      o.order_number,
      o.business_name_snapshot as business_name,
      count(oi.id)::integer as item_count,
      o.total,
      o.created_at
    from public.orders o
    left join public.order_items oi on oi.order_id = o.id
    where o.status = 'pending'
    group by
      o.id,
      o.order_number,
      o.business_name_snapshot,
      o.total,
      o.created_at
    order by o.created_at desc
    limit 5
  ),
  low_stock_rows as (
    select *
    from available_products
    where available_quantity between 1 and 10
    order by available_quantity, name
    limit 5
  )
  select jsonb_build_object(
    'stats',
    jsonb_build_object(
      'total_customers',
      (select count(*) from public.business_customers),
      'active_customers',
      (
        select count(*)
        from public.business_customers c
        where c.account_status = 'active'
          and c.archived_at is null
      ),
      'pending_orders',
      (select count(*) from public.orders o where o.status = 'pending'),
      'today_orders',
      (
        select count(*)
        from public.orders o
        where timezone('Africa/Tripoli', o.created_at)::date =
          timezone('Africa/Tripoli', now())::date
      ),
      'low_stock_count',
      (
        select count(*)
        from available_products
        where available_quantity between 1 and 10
      ),
      'month_sales',
      coalesce(
        (
          select sum(o.total)
          from public.orders o
          where o.status = 'delivered'
            and date_trunc(
              'month',
              timezone('Africa/Tripoli', o.created_at)
            ) = date_trunc('month', timezone('Africa/Tripoli', now()))
        ),
        0
      )
    ),
    'pending_orders',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', row.id,
            'order_number', row.order_number,
            'business_name', row.business_name,
            'item_count', row.item_count,
            'total', row.total,
            'created_at', row.created_at
          )
          order by row.created_at desc
        )
        from pending_rows row
      ),
      '[]'::jsonb
    ),
    'low_stock_products',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'product_id', row.id,
            'product_name', row.name,
            'sku', row.sku,
            'available_quantity', row.available_quantity
          )
          order by row.available_quantity, row.name
        )
        from low_stock_rows row
      ),
      '[]'::jsonb
    )
  )
  into result;

  return result;
end;
$$;

create or replace function public.admin_operational_report(
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  actor_role text;
  effective_to timestamptz := coalesce(p_to, now());
  result jsonb;
begin
  actor_role := public.current_role();
  if actor_role is distinct from 'admin' then
    raise exception 'ADMIN_REQUIRED'
      using errcode = '42501';
  end if;
  if p_from is not null and p_from > effective_to then
    raise exception 'INVALID_REPORT_PERIOD'
      using errcode = '22023';
  end if;

  with filtered_orders as (
    select o.*
    from public.orders o
    where (p_from is null or o.created_at >= p_from)
      and o.created_at <= effective_to
  ),
  delivered_orders as (
    select *
    from filtered_orders
    where status = 'delivered'
  ),
  available_products as (
    select
      p.id,
      p.name,
      p.sku,
      greatest(
        p.stock_quantity - coalesce(
          sum(r.quantity) filter (where r.status = 'active'),
          0
        ),
        0
      )::integer as available_quantity
    from public.products p
    left join public.inventory_reservations r
      on r.product_id = p.id
      and r.status = 'active'
    where p.active
      and p.archived_at is null
    group by p.id, p.name, p.sku, p.stock_quantity
  ),
  top_customer_rows as (
    select
      c.id as customer_id,
      c.business_name,
      count(o.id)::integer as order_count,
      coalesce(sum(o.total), 0) as sales_total
    from delivered_orders o
    join public.business_customers c on c.id = o.customer_id
    group by c.id, c.business_name
    order by sales_total desc, order_count desc, c.business_name
    limit 10
  ),
  top_product_rows as (
    select
      p.id as product_id,
      p.name as product_name,
      p.sku,
      coalesce(sum(oi.quantity), 0)::integer as quantity,
      coalesce(sum(oi.line_total), 0) as sales_total
    from delivered_orders o
    join public.order_items oi on oi.order_id = o.id
    join public.products p on p.id = oi.product_id
    group by p.id, p.name, p.sku
    order by quantity desc, sales_total desc, p.name
    limit 10
  ),
  low_stock_rows as (
    select *
    from available_products
    where available_quantity between 0 and 10
    order by available_quantity, name
    limit 20
  ),
  outstanding_rows as (
    select
      c.id as customer_id,
      c.business_name,
      c.outstanding_balance,
      c.credit_limit
    from public.business_customers c
    where c.outstanding_balance > 0
      and c.account_status <> 'archived'
    order by c.outstanding_balance desc, c.business_name
    limit 20
  )
  select jsonb_build_object(
    'period_order_count',
    (select count(*) from filtered_orders),
    'delivered_order_count',
    (select count(*) from delivered_orders),
    'cancelled_order_count',
    (
      select count(*)
      from filtered_orders
      where status = 'cancelled'
    ),
    'sales_total',
    coalesce((select sum(total) from delivered_orders), 0),
    'average_order_value',
    coalesce((select avg(total) from delivered_orders), 0),
    'outstanding_balance',
    coalesce(
      (
        select sum(c.outstanding_balance)
        from public.business_customers c
        where c.account_status <> 'archived'
      ),
      0
    ),
    'top_customers',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'customer_id', row.customer_id,
            'business_name', row.business_name,
            'order_count', row.order_count,
            'sales_total', row.sales_total
          )
          order by row.sales_total desc, row.order_count desc
        )
        from top_customer_rows row
      ),
      '[]'::jsonb
    ),
    'top_products',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'product_id', row.product_id,
            'product_name', row.product_name,
            'sku', row.sku,
            'quantity', row.quantity,
            'sales_total', row.sales_total
          )
          order by row.quantity desc, row.sales_total desc
        )
        from top_product_rows row
      ),
      '[]'::jsonb
    ),
    'low_stock_products',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'product_id', row.id,
            'product_name', row.name,
            'sku', row.sku,
            'available_quantity', row.available_quantity
          )
          order by row.available_quantity, row.name
        )
        from low_stock_rows row
      ),
      '[]'::jsonb
    ),
    'outstanding_customers',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'customer_id', row.customer_id,
            'business_name', row.business_name,
            'outstanding_balance', row.outstanding_balance,
            'credit_limit', row.credit_limit
          )
          order by row.outstanding_balance desc, row.business_name
        )
        from outstanding_rows row
      ),
      '[]'::jsonb
    )
  )
  into result;

  return result;
end;
$$;

revoke all on function public.admin_dashboard_snapshot()
  from public, anon, authenticated;
revoke all on function public.admin_operational_report(timestamptz, timestamptz)
  from public, anon, authenticated;

grant execute on function public.admin_dashboard_snapshot()
  to authenticated;
grant execute on function public.admin_operational_report(timestamptz, timestamptz)
  to authenticated;

comment on function public.admin_dashboard_snapshot() is
  'Bounded staff/admin dashboard metrics and preview rows.';
comment on function public.admin_operational_report(timestamptz, timestamptz) is
  'Admin-only operational aggregate report; balances are manually maintained references.';

notify pgrst, 'reload schema';
