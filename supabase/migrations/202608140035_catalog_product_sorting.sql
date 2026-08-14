-- Add deterministic server-side catalog sorting without changing the existing
-- RLS-scoped filters, category archive defenses, or response contract.

begin;

drop function if exists public.catalog_products_page(
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
);

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
  p_limit integer default 50,
  p_sort text default 'newest'
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
  v_sort text := case lower(btrim(coalesce(p_sort, 'newest')))
    when 'newest' then 'newest'
    when 'oldest' then 'oldest'
    when 'name_asc' then 'name_asc'
    when 'price_asc' then 'price_asc'
    when 'price_desc' then 'price_desc'
    when 'stock_asc' then 'stock_asc'
    when 'stock_desc' then 'stock_desc'
    else 'newest'
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
      p.archived_by_category_id,
      p.active_before_category_archive,
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
          and (
            p.category_id is null
            or (
              c.id is not null
              and c.active
              and c.archived_at is null
            )
          )
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
  ordered as (
    select
      filtered.*,
      row_number() over (
        order by
          case
            when v_sort = 'newest' then filtered.created_at
          end desc nulls last,
          case
            when v_sort = 'newest' then filtered.id
          end desc,
          case
            when v_sort = 'oldest' then filtered.created_at
          end asc nulls last,
          case
            when v_sort = 'oldest' then filtered.id
          end asc,
          case
            when v_sort = 'name_asc'
              then lower(btrim(coalesce(filtered.name, '')))
          end asc,
          case
            when v_sort = 'name_asc' then filtered.id
          end asc,
          case
            when v_sort = 'price_asc' then filtered.effective_price
          end asc nulls last,
          case
            when v_sort = 'price_asc' then filtered.id
          end asc,
          case
            when v_sort = 'price_desc' then filtered.effective_price
          end desc nulls last,
          case
            when v_sort = 'price_desc' then filtered.id
          end desc,
          case
            when v_sort in ('stock_asc', 'stock_desc') then
              case
                when filtered.stock_tracking_enabled then 0
                else 1
              end
          end asc,
          case
            when v_sort = 'stock_asc' then filtered.available_quantity
          end asc nulls last,
          case
            when v_sort = 'stock_asc' then filtered.id
          end asc,
          case
            when v_sort = 'stock_desc' then filtered.available_quantity
          end desc nulls last,
          case
            when v_sort = 'stock_desc' then filtered.id
          end desc
      ) as sort_position
    from filtered
  ),
  candidates as (
    select ordered.*
    from ordered
    order by ordered.sort_position
    offset v_offset
    limit v_limit + 1
  ),
  page_rows as (
    select candidates.*
    from candidates
    order by candidates.sort_position
    limit v_limit
  )
  select jsonb_build_object(
    'snapshot_at', v_snapshot_at,
    'products', coalesce(
      (
        select jsonb_agg(
          to_jsonb(page_rows) - 'sort_position'
          order by page_rows.sort_position
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
  integer,
  text
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
  integer,
  text
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
  integer,
  text
) is
  'Returns one RLS-scoped catalog page with category archive defenses and deterministic newest, oldest, name, price, or available-stock sorting.';

notify pgrst, 'reload schema';

commit;
