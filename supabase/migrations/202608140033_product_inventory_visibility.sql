-- Add an explicit product-level preference for showing exact inventory counts
-- to customers. Inventory, reservation, pricing, filtering, and order behavior
-- remain unchanged.

begin;

alter table public.products
  add column if not exists show_stock_quantity_to_customers boolean;

update public.products
set show_stock_quantity_to_customers = false
where show_stock_quantity_to_customers is null;

alter table public.products
  alter column show_stock_quantity_to_customers set default false,
  alter column show_stock_quantity_to_customers set not null;

comment on column public.products.show_stock_quantity_to_customers is
  'When true, customer-facing interfaces may show the exact stock quantity; false keeps the count hidden from customers.';

drop function if exists public.catalog_products(uuid);

create function public.catalog_products(
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
  units_per_box integer,
  base_price numeric,
  retail_unit_price numeric,
  effective_price numeric,
  old_price numeric,
  discount_percent integer,
  stock_quantity integer,
  show_stock_quantity_to_customers boolean,
  stock_tracking_enabled boolean,
  hide_when_out_of_stock boolean,
  available_quantity integer,
  is_orderable boolean,
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
    p.units_per_box,
    p.base_price,
    p.retail_unit_price,
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
    p.show_stock_quantity_to_customers,
    p.stock_tracking_enabled,
    p.hide_when_out_of_stock,
    case
      when p.stock_tracking_enabled then greatest(
        p.stock_quantity - reserved.active_reserved_quantity,
        0
      )::integer
      else null
    end as available_quantity,
    (
      not p.stock_tracking_enabled
      or greatest(
        p.stock_quantity - reserved.active_reserved_quantity,
        0
      ) >= p.min_order_quantity
    ) as is_orderable,
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
  cross join lateral (
    select public.catalog_active_reserved_quantity(p.id)
      as active_reserved_quantity
  ) reserved
  left join public.categories c on c.id = p.category_id
  where (
      actor.role in ('admin', 'staff')
      or (
        actor.role = 'customer'
        and actor.customer_id is not null
        and p.active
        and p.archived_at is null
      )
    )
    and (
      actor.role <> 'customer'
      or not p.stock_tracking_enabled
      or not p.hide_when_out_of_stock
      or greatest(
        p.stock_quantity - reserved.active_reserved_quantity,
        0
      ) >= p.min_order_quantity
    )
    and (p_product_id is null or p.id = p_product_id)
  order by p.created_at desc;
$$;

revoke all on function public.catalog_products(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.catalog_products(uuid) to authenticated;

comment on function public.catalog_products(uuid) is
  'Returns caller-visible products with tracked nullable availability, orderability, customer stock-count visibility, and customer out-of-stock hiding.';

create or replace function public.catalog_products_page(
  p_query text default '',
  p_category text default null,
  p_brand text default null,
  p_animal_type text default null,
  p_unit_size text default null,
  p_min_price numeric default null,
  p_max_price numeric default null,
  p_availability text default 'all',
  p_include_inactive boolean default false,
  p_snapshot_at timestamptz default null,
  p_offset integer default 0,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_query text := lower(btrim(coalesce(p_query, '')));
  v_category text := nullif(btrim(coalesce(p_category, '')), '');
  v_brand text := nullif(btrim(coalesce(p_brand, '')), '');
  v_animal_type text := nullif(btrim(coalesce(p_animal_type, '')), '');
  v_unit_size text := nullif(btrim(coalesce(p_unit_size, '')), '');
  v_availability text := case
    when p_availability in ('all', 'in_stock', 'low_stock', 'out_of_stock')
      then p_availability
    else 'all'
  end;
  v_snapshot_at timestamptz := coalesce(
    p_snapshot_at,
    statement_timestamp()
  );
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_result jsonb;
begin
  with actor as (
    select
      public.current_role() as role,
      public.current_customer_id() as customer_id
  ),
  catalog as materialized (
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
      p.units_per_box,
      p.base_price,
      p.retail_unit_price,
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
      p.show_stock_quantity_to_customers,
      p.stock_tracking_enabled,
      p.hide_when_out_of_stock,
      case
        when p.stock_tracking_enabled then greatest(
          p.stock_quantity - reserved.active_reserved_quantity,
          0
        )::integer
        else null
      end as available_quantity,
      (
        not p.stock_tracking_enabled
        or greatest(
          p.stock_quantity - reserved.active_reserved_quantity,
          0
        ) >= p.min_order_quantity
      ) as is_orderable,
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
    cross join lateral (
      select public.catalog_active_reserved_quantity(p.id)
        as active_reserved_quantity
    ) reserved
    left join public.categories c on c.id = p.category_id
    where p.created_at <= v_snapshot_at
      and (
        (
          actor.role in ('admin', 'staff')
          and (
            coalesce(p_include_inactive, false)
            or (p.active and p.archived_at is null)
          )
        )
        or (
          actor.role = 'customer'
          and actor.customer_id is not null
          and p.active
          and p.archived_at is null
        )
      )
      and (
        actor.role <> 'customer'
        or not p.stock_tracking_enabled
        or not p.hide_when_out_of_stock
        or greatest(
          p.stock_quantity - reserved.active_reserved_quantity,
          0
        ) >= p.min_order_quantity
      )
  ),
  filtered as (
    select catalog.*
    from catalog
    where (
        v_query = ''
        or strpos(lower(coalesce(catalog.name, '')), v_query) > 0
        or strpos(lower(coalesce(catalog.brand, '')), v_query) > 0
        or (
          (select role from actor) in ('admin', 'staff')
          and (
            strpos(lower(coalesce(catalog.name_en, '')), v_query) > 0
            or strpos(lower(coalesce(catalog.sku, '')), v_query) > 0
            or strpos(
              lower(coalesce(catalog.category_name, '')),
              v_query
            ) > 0
            or exists (
              select 1
              from unnest(
                coalesce(catalog.tags, '{}'::text[])
              ) as tag(value)
              where strpos(lower(tag.value), v_query) > 0
            )
          )
        )
      )
      and (v_category is null or catalog.category_name = v_category)
      and (v_brand is null or catalog.brand = v_brand)
      and (v_animal_type is null or catalog.animal_type = v_animal_type)
      and (
        v_unit_size is null
        or coalesce(catalog.package_size, catalog.unit_size) = v_unit_size
      )
      and (p_min_price is null or catalog.effective_price >= p_min_price)
      and (p_max_price is null or catalog.effective_price <= p_max_price)
      and (
        v_availability = 'all'
        or (
          v_availability = 'in_stock'
          and catalog.is_orderable
        )
        or (
          v_availability = 'low_stock'
          and catalog.stock_tracking_enabled
          and catalog.is_orderable
          and catalog.available_quantity <= 10
        )
        or (
          v_availability = 'out_of_stock'
          and catalog.stock_tracking_enabled
          and not catalog.is_orderable
        )
      )
  ),
  candidates as (
    select filtered.*
    from filtered
    order by filtered.created_at desc, filtered.id desc
    offset v_offset
    limit v_limit + 1
  ),
  page_rows as (
    select candidates.*
    from candidates
    order by candidates.created_at desc, candidates.id desc
    limit v_limit
  )
  select jsonb_build_object(
    'snapshot_at', v_snapshot_at,
    'products', coalesce(
      (
        select jsonb_agg(
          to_jsonb(page_rows)
          order by page_rows.created_at desc, page_rows.id desc
        )
        from page_rows
      ),
      '[]'::jsonb
    ),
    'has_more', (select count(*) > v_limit from candidates),
    'next_offset', v_offset + (select count(*) from page_rows)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.catalog_products_page(
  text,
  text,
  text,
  text,
  text,
  numeric,
  numeric,
  text,
  boolean,
  timestamptz,
  integer,
  integer
) from public, anon, authenticated, service_role;

grant execute on function public.catalog_products_page(
  text,
  text,
  text,
  text,
  text,
  numeric,
  numeric,
  text,
  boolean,
  timestamptz,
  integer,
  integer
) to authenticated;

comment on function public.catalog_products_page(
  text,
  text,
  text,
  text,
  text,
  numeric,
  numeric,
  text,
  boolean,
  timestamptz,
  integer,
  integer
) is
  'Returns one RLS-scoped page with nullable tracked availability, customer stock-count visibility, and customer out-of-stock hiding.';

commit;
