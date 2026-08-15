-- Return catalog rows with the current caller's authoritative display price.
-- The function is security invoker so all underlying table reads remain
-- constrained by the caller's existing RLS policies.

create or replace function public.catalog_products(
  p_product_id uuid default null
)
returns table (
  id uuid,
  category_id uuid,
  category_name text,
  name text,
  name_en text,
  sku text,
  barcode text,
  brand text,
  description text,
  animal_type text,
  unit_size text,
  package_size text,
  base_price numeric,
  effective_price numeric,
  old_price numeric,
  discount_percent integer,
  stock_quantity integer,
  available_quantity integer,
  min_order_quantity integer,
  image_url text,
  source_url text,
  tags text[],
  active boolean,
  is_featured boolean,
  is_top_selling boolean,
  archived_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  with actor as (
    select
      public.current_role() as role,
      public.current_customer_id() as customer_id
  )
  select
    p.id,
    p.category_id,
    c.name as category_name,
    p.name,
    p.name_en,
    p.sku,
    p.barcode,
    p.brand,
    p.description,
    p.animal_type,
    p.unit_size,
    p.package_size,
    p.base_price,
    case
      when actor.role = 'customer' then coalesce(
        (
          select special.price
          from public.customer_special_prices special
          where special.customer_id = actor.customer_id
            and special.product_id = p.id
            and special.active
          limit 1
        ),
        (
          select grouped.price
          from public.business_customers customer
          join public.product_prices grouped
            on grouped.price_group_id = customer.price_group_id
          where customer.id = actor.customer_id
            and grouped.product_id = p.id
          limit 1
        ),
        p.base_price
      )
      else p.base_price
    end as effective_price,
    p.old_price,
    p.discount_percent,
    p.stock_quantity,
    greatest(
      p.stock_quantity - coalesce(
        (
          select sum(r.quantity)
          from public.inventory_reservations r
          where r.product_id = p.id
            and r.status = 'active'
        ),
        0
      ),
      0
    )::integer as available_quantity,
    p.min_order_quantity,
    p.image_url,
    p.source_url,
    p.tags,
    p.active,
    p.is_featured,
    p.is_top_selling,
    p.archived_at,
    p.created_at,
    p.updated_at
  from public.products p
  cross join actor
  left join public.categories c on c.id = p.category_id
  where (
      actor.role in ('admin', 'staff')
      or (
        actor.role = 'customer'
        and actor.customer_id is not null
      )
    )
    and (p_product_id is null or p.id = p_product_id)
  order by p.created_at desc;
$$;

revoke all on function public.catalog_products(uuid)
  from public, anon, authenticated;
grant execute on function public.catalog_products(uuid) to authenticated;

notify pgrst, 'reload schema';
