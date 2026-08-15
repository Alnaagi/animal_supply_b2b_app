-- Add simple product packaging/visibility controls while keeping inventory
-- authority inside the existing server-side ordering transactions.
--
-- `units_per_box` and `retail_unit_price` are display/reference metadata only.
-- `base_price` / the customer effective price remain the authoritative
-- wholesale order price. Order quantities, reservations, and stock quantities
-- continue to use the existing sellable product unit.

begin;

alter table public.products
  add column if not exists units_per_box integer,
  add column if not exists retail_unit_price numeric(12,2),
  add column if not exists stock_tracking_enabled boolean,
  add column if not exists hide_when_out_of_stock boolean;

update public.products
set
  stock_tracking_enabled = coalesce(stock_tracking_enabled, true),
  hide_when_out_of_stock = coalesce(hide_when_out_of_stock, false)
where stock_tracking_enabled is null
  or hide_when_out_of_stock is null;

alter table public.products
  alter column stock_tracking_enabled set default true,
  alter column stock_tracking_enabled set not null,
  alter column hide_when_out_of_stock set default false,
  alter column hide_when_out_of_stock set not null;

alter table public.order_items
  add column if not exists units_per_box_snapshot integer,
  add column if not exists retail_unit_price_snapshot numeric(12,2),
  add column if not exists stock_tracking_enabled_snapshot boolean;

update public.order_items
set stock_tracking_enabled_snapshot = true
where stock_tracking_enabled_snapshot is null;

alter table public.order_items
  alter column stock_tracking_enabled_snapshot set default true,
  alter column stock_tracking_enabled_snapshot set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_units_per_box_positive'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_units_per_box_positive
      check (
        units_per_box is null
        or units_per_box between 1 and 1000000
      )
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_moq_supported_range'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_moq_supported_range
      check (min_order_quantity between 1 and 1000000)
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_retail_unit_price_positive'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_retail_unit_price_positive
      check (retail_unit_price is null or retail_unit_price > 0)
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'order_items_units_per_box_snapshot_positive'
      and conrelid = 'public.order_items'::regclass
  ) then
    alter table public.order_items
      add constraint order_items_units_per_box_snapshot_positive
      check (
        units_per_box_snapshot is null
        or units_per_box_snapshot between 1 and 1000000
      )
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'order_items_retail_unit_price_snapshot_positive'
      and conrelid = 'public.order_items'::regclass
  ) then
    alter table public.order_items
      add constraint order_items_retail_unit_price_snapshot_positive
      check (
        retail_unit_price_snapshot is null
        or retail_unit_price_snapshot > 0
      )
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'order_items_quantity_supported_range'
      and conrelid = 'public.order_items'::regclass
  ) then
    alter table public.order_items
      add constraint order_items_quantity_supported_range
      check (quantity between 1 and 1000000)
      not valid;
  end if;
end
$$;

alter table public.products
  validate constraint products_units_per_box_positive,
  validate constraint products_retail_unit_price_positive,
  validate constraint products_moq_supported_range;
alter table public.order_items
  validate constraint order_items_units_per_box_snapshot_positive,
  validate constraint order_items_retail_unit_price_snapshot_positive,
  validate constraint order_items_quantity_supported_range;

comment on column public.products.units_per_box is
  'Optional display-only number of sellable units in one box; never changes price or stock arithmetic.';
comment on column public.products.retail_unit_price is
  'Optional suggested reseller price for one retail unit; reference-only and never used in wholesale order totals.';
comment on column public.products.stock_tracking_enabled is
  'When false, orders remain reservable/auditable but are not limited by or deducted from stock.';
comment on column public.products.hide_when_out_of_stock is
  'When true, customers do not see a tracked product whose available quantity is below its minimum order quantity.';
comment on column public.order_items.units_per_box_snapshot is
  'Historical copy of products.units_per_box at order creation.';
comment on column public.order_items.retail_unit_price_snapshot is
  'Historical reference-only copy of products.retail_unit_price at order creation.';
comment on column public.order_items.stock_tracking_enabled_snapshot is
  'Historical inventory behavior for the order line; only true snapshots consume or decrement stock.';

create or replace function public.catalog_active_reserved_quantity(
  p_product_id uuid
)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with actor as (
    select public.current_role() as role
  ),
  visible_product as (
    select p.id
    from public.products p
    cross join actor
    where p.id = p_product_id
      and (
        actor.role in ('admin', 'staff')
        or (
          actor.role = 'customer'
          and p.active
          and p.archived_at is null
        )
      )
  )
  select coalesce(
    sum(r.quantity) filter (
      where oi.stock_tracking_enabled_snapshot
    ),
    0
  )::integer
  from visible_product p
  left join public.inventory_reservations r
    on r.product_id = p.id
    and r.status = 'active'
  left join public.order_items oi
    on oi.id = r.order_item_id
    and oi.order_id = r.order_id
    and oi.product_id = r.product_id
    and oi.quantity = r.quantity
$$;

revoke all on function public.catalog_active_reserved_quantity(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.catalog_active_reserved_quantity(uuid)
  to authenticated;

comment on function public.catalog_active_reserved_quantity(uuid) is
  'Returns tracked active reservations only for a catalog-visible product.';

drop policy if exists "products active readable" on public.products;
create policy "products active readable"
on public.products
for select
using (
  public.is_active_actor()
  and (
    public.is_staff_or_admin()
    or (
      active
      and archived_at is null
      and (
        not stock_tracking_enabled
        or not hide_when_out_of_stock
        or greatest(
          stock_quantity
            - public.catalog_active_reserved_quantity(id),
          0
        ) >= min_order_quantity
      )
    )
  )
);

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
  'Returns caller-visible products with tracked nullable availability, orderability, and customer out-of-stock hiding.';

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
  'Returns one RLS-scoped page with nullable tracked availability and customer out-of-stock hiding.';

create or replace function public.catalog_product_filter_options(
  p_include_inactive boolean default false
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with actor as (
    select
      public.current_role() as role,
      public.current_customer_id() as customer_id
  ),
  visible as materialized (
    select
      c.name as category,
      btrim(coalesce(p.brand, '')) as brand,
      btrim(coalesce(p.animal_type, '')) as animal_type,
      btrim(coalesce(p.package_size, p.unit_size, '')) as unit_size
    from public.products p
    cross join actor
    cross join lateral (
      select public.catalog_active_reserved_quantity(p.id)
        as active_reserved_quantity
    ) reserved
    left join public.categories c on c.id = p.category_id
    where (
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
  )
  select jsonb_build_object(
    'categories', coalesce(
      (
        select jsonb_agg(value order by value)
        from (
          select distinct btrim(category) as value
          from visible
          where btrim(coalesce(category, '')) <> ''
        ) categories
      ),
      '[]'::jsonb
    ),
    'brands', coalesce(
      (
        select jsonb_agg(value order by value)
        from (
          select distinct brand as value
          from visible
          where brand <> ''
        ) brands
      ),
      '[]'::jsonb
    ),
    'animal_types', coalesce(
      (
        select jsonb_agg(value order by value)
        from (
          select distinct animal_type as value
          from visible
          where animal_type <> ''
        ) animal_types
      ),
      '[]'::jsonb
    ),
    'unit_sizes', coalesce(
      (
        select jsonb_agg(value order by value)
        from (
          select distinct unit_size as value
          from visible
          where unit_size <> ''
        ) unit_sizes
      ),
      '[]'::jsonb
    )
  );
$$;

revoke all on function public.catalog_product_filter_options(boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.catalog_product_filter_options(boolean)
  to authenticated;

comment on function public.catalog_product_filter_options(boolean) is
  'Returns facets from caller-visible products after customer out-of-stock hiding.';

create or replace function public.protect_product_stock_tracking_toggle()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_active_tracked_quantity integer;
begin
  if new.stock_tracking_enabled is not distinct from old.stock_tracking_enabled
  then
    return new;
  end if;

  if old.stock_tracking_enabled and not new.stock_tracking_enabled then
    select coalesce(sum(r.quantity), 0)::integer
    into v_active_tracked_quantity
    from public.inventory_reservations r
    join public.order_items oi
      on oi.id = r.order_item_id
      and oi.order_id = r.order_id
      and oi.product_id = r.product_id
      and oi.quantity = r.quantity
    where r.product_id = old.id
      and r.status = 'active'
      and oi.stock_tracking_enabled_snapshot;

    if v_active_tracked_quantity > 0 then
      raise exception using
        errcode = 'P0001',
        message = 'STOCK_TRACKING_HAS_ACTIVE_RESERVATIONS',
        detail = jsonb_build_object(
          'product_id', old.id,
          'active_tracked_quantity', v_active_tracked_quantity
        )::text;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.protect_product_stock_tracking_toggle()
  from public, anon, authenticated, service_role;

drop trigger if exists protect_product_stock_tracking_toggle
  on public.products;
create trigger protect_product_stock_tracking_toggle
before update of stock_tracking_enabled on public.products
for each row
execute function public.protect_product_stock_tracking_toggle();

comment on function public.protect_product_stock_tracking_toggle() is
  'Prevents disabling stock tracking while historical tracked order lines still have active reservations.';

create or replace function public.order_payload(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id', o.id,
    'order_number', o.order_number,
    'client_request_id', o.client_request_id,
    'customer_id', o.customer_id,
    'customer_profile_id', o.customer_profile_id,
    'customer_name', o.contact_person_snapshot,
    'business_name', o.business_name_snapshot,
    'contact_person', o.contact_person_snapshot,
    'contact_phone', o.contact_phone_snapshot,
    'status', o.status,
    'subtotal', o.subtotal,
    'delivery_fee', o.delivery_fee,
    'handling_fee', o.handling_fee,
    'total', o.total,
    'delivery_address', o.delivery_address,
    'delivery_note', coalesce(o.delivery_note, ''),
    'customer_note', coalesce(o.customer_note, ''),
    'notes', coalesce(o.customer_note, ''),
    'admin_note', coalesce(o.admin_note, ''),
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    'items', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', oi.id,
            'product_id', oi.product_id,
            'product_name', oi.product_name_snapshot,
            'product_sku', oi.product_sku_snapshot,
            'sku', oi.product_sku_snapshot,
            'unit_size', oi.unit_size_snapshot,
            'package_label', oi.package_label_snapshot,
            'units_per_box', oi.units_per_box_snapshot,
            'retail_unit_price', oi.retail_unit_price_snapshot,
            'stock_tracking_enabled',
            oi.stock_tracking_enabled_snapshot,
            'quantity', oi.quantity,
            'unit_price', oi.unit_price,
            'line_total', oi.line_total
          )
          order by oi.created_at, oi.id
        )
        from public.order_items oi
        where oi.order_id = o.id
      ),
      '[]'::jsonb
    )
  )
  from public.orders o
  where o.id = p_order_id
$$;

comment on function public.order_payload(uuid) is
  'Returns an order with immutable wholesale, packaging, retail-reference, and inventory-behavior line snapshots.';

create or replace function public.place_order_transaction_impl(
  p_actor_id uuid,
  p_client_request_id uuid,
  p_items jsonb,
  p_delivery_address text default null,
  p_customer_note text default null,
  p_delivery_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_role text;
  customer public.business_customers%rowtype;
  existing_order_id uuid;
  new_order_id uuid;
  new_order_number text;
  item record;
  product public.products%rowtype;
  order_item_id uuid;
  effective_price numeric(12,2);
  reserved_quantity integer;
  subtotal_amount numeric(12,2) := 0;
  minimum_order_amount numeric(12,2);
  configured_delivery_fee numeric(12,2);
  configured_handling_fee numeric(12,2);
  resolved_delivery_address text;
  recipient record;
begin
  if p_actor_id is null then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;

  if p_client_request_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'CLIENT_REQUEST_ID_REQUIRED';
  end if;

  if p_items is null
    or jsonb_typeof(p_items) <> 'array'
    or jsonb_array_length(p_items) = 0
  then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_ITEMS_REQUIRED';
  end if;

  if jsonb_array_length(p_items) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'TOO_MANY_ORDER_ITEMS';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items)
      as parsed(product_id uuid, quantity integer)
    where parsed.product_id is null
      or parsed.quantity is null
      or parsed.quantity <= 0
      or parsed.quantity > 1000000
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'INVALID_ORDER_ITEM';
  end if;

  select c.*
  into customer
  from public.business_customers c
  join public.profiles p on p.id = c.profile_id
  where p.id = p_actor_id
    and p.active
    and not p.must_change_password
    and p.role = 'customer'
  for update of c;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_ACCOUNT_NOT_FOUND';
  end if;

  actor_role := 'customer';

  if customer.account_status <> 'active' then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_ACCOUNT_INACTIVE',
      detail = coalesce(
        customer.ordering_block_reason,
        customer.account_status
      );
  end if;

  select o.id
  into existing_order_id
  from public.orders o
  where o.customer_id = customer.id
    and o.client_request_id = p_client_request_id;

  if existing_order_id is not null then
    return jsonb_build_object(
      'order', public.order_payload(existing_order_id),
      'idempotent', true
    );
  end if;

  if length(coalesce(p_customer_note, '')) > 1000
    or length(coalesce(p_delivery_note, '')) > 1000
    or length(coalesce(p_delivery_address, '')) > 500
  then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_TEXT_TOO_LONG';
  end if;

  minimum_order_amount := greatest(
    public.app_setting_numeric('minimum_order_amount', 0),
    0
  );
  configured_delivery_fee := greatest(
    public.app_setting_numeric('delivery_fee', 0),
    0
  );
  configured_handling_fee := greatest(
    public.app_setting_numeric('handling_fee', 0),
    0
  );
  resolved_delivery_address := coalesce(
    nullif(trim(p_delivery_address), ''),
    nullif(trim(customer.address), ''),
    ''
  );
  new_order_number := 'AS-'
    || to_char(now() at time zone 'Africa/Tripoli', 'YYYYMMDD')
    || '-'
    || lpad(nextval('public.order_number_seq')::text, 6, '0');

  insert into public.orders (
    order_number,
    client_request_id,
    customer_id,
    customer_profile_id,
    business_name_snapshot,
    contact_person_snapshot,
    contact_phone_snapshot,
    status,
    subtotal,
    delivery_fee,
    handling_fee,
    delivery_address,
    delivery_note,
    customer_note,
    placed_by
  )
  values (
    new_order_number,
    p_client_request_id,
    customer.id,
    customer.profile_id,
    customer.business_name,
    coalesce(customer.contact_person, ''),
    coalesce(customer.phone, ''),
    'pending',
    0,
    configured_delivery_fee,
    configured_handling_fee,
    resolved_delivery_address,
    nullif(trim(p_delivery_note), ''),
    nullif(trim(p_customer_note), ''),
    p_actor_id
  )
  returning id into new_order_id;

  for item in
    select
      parsed.product_id,
      sum(parsed.quantity)::integer as quantity
    from jsonb_to_recordset(p_items)
      as parsed(product_id uuid, quantity integer)
    group by parsed.product_id
    order by parsed.product_id
  loop
    if item.product_id is null
      or item.quantity is null
      or item.quantity <= 0
      or item.quantity > 1000000
    then
      raise exception using
        errcode = 'P0001',
        message = 'INVALID_ORDER_ITEM';
    end if;

    select p.*
    into product
    from public.products p
    where p.id = item.product_id
    for update;

    if not found
      or not product.active
      or product.archived_at is not null
    then
      raise exception using
        errcode = 'P0001',
        message = 'PRODUCT_UNAVAILABLE',
        detail = item.product_id::text;
    end if;

    if item.quantity < product.min_order_quantity then
      raise exception using
        errcode = 'P0001',
        message = 'MINIMUM_QUANTITY_NOT_MET',
        detail = jsonb_build_object(
          'product_id', product.id,
          'minimum_quantity', product.min_order_quantity,
          'requested_quantity', item.quantity
        )::text;
    end if;

    reserved_quantity := 0;
    if product.stock_tracking_enabled then
      select coalesce(sum(r.quantity), 0)::integer
      into reserved_quantity
      from public.inventory_reservations r
      join public.order_items oi
        on oi.id = r.order_item_id
        and oi.order_id = r.order_id
        and oi.product_id = r.product_id
        and oi.quantity = r.quantity
      where r.product_id = product.id
        and r.status = 'active'
        and oi.stock_tracking_enabled_snapshot;

      if product.stock_quantity - reserved_quantity < item.quantity then
        raise exception using
          errcode = 'P0001',
          message = 'INSUFFICIENT_STOCK',
          detail = jsonb_build_object(
            'product_id', product.id,
            'available_quantity',
            greatest(product.stock_quantity - reserved_quantity, 0),
            'requested_quantity', item.quantity
          )::text;
      end if;
    end if;

    effective_price := public.effective_product_price(
      customer.id,
      product.id
    );
    if effective_price is null or effective_price <= 0 then
      raise exception using
        errcode = 'P0001',
        message = 'PRODUCT_PRICE_UNAVAILABLE',
        detail = product.id::text;
    end if;

    insert into public.order_items (
      order_id,
      product_id,
      product_name_snapshot,
      product_sku_snapshot,
      unit_size_snapshot,
      package_label_snapshot,
      units_per_box_snapshot,
      retail_unit_price_snapshot,
      stock_tracking_enabled_snapshot,
      quantity,
      unit_price
    )
    values (
      new_order_id,
      product.id,
      product.name,
      product.sku,
      coalesce(product.unit_size, ''),
      coalesce(
        nullif(product.package_size, ''),
        nullif(product.unit_size, ''),
        ''
      ),
      product.units_per_box,
      product.retail_unit_price,
      product.stock_tracking_enabled,
      item.quantity,
      effective_price
    )
    returning id into order_item_id;

    -- Every line receives exactly one reservation for auditability and status
    -- integrity. The snapshot decides whether it consumes physical stock.
    insert into public.inventory_reservations (
      order_id,
      order_item_id,
      product_id,
      quantity
    )
    values (
      new_order_id,
      order_item_id,
      product.id,
      item.quantity
    );

    subtotal_amount := subtotal_amount + (effective_price * item.quantity);
  end loop;

  if subtotal_amount < minimum_order_amount then
    raise exception using
      errcode = 'P0001',
      message = 'MINIMUM_ORDER_AMOUNT_NOT_MET',
      detail = jsonb_build_object(
        'minimum_order_amount', minimum_order_amount,
        'subtotal', subtotal_amount
      )::text;
  end if;

  update public.orders
  set subtotal = subtotal_amount
  where id = new_order_id;

  insert into public.order_status_history (
    order_id,
    from_status,
    to_status,
    note,
    changed_by,
    changed_by_role
  )
  values (
    new_order_id,
    null,
    'pending',
    'تم إرسال الطلب من العميل',
    p_actor_id,
    actor_role
  );

  for recipient in
    select p.id, p.role
    from public.profiles p
    where p.active
      and p.role in ('admin', 'staff')
  loop
    perform public.enqueue_notification(
      recipient.id,
      recipient.role,
      'new_order',
      'طلب جديد',
      customer.business_name || ' أرسل الطلب ' || new_order_number
        || ' بقيمة ' || to_char(
          subtotal_amount
            + configured_delivery_fee
            + configured_handling_fee,
          'FM999999990.00'
        ) || ' د.ل',
      jsonb_build_object(
        'order_id', new_order_id,
        'order_number', new_order_number,
        'status', 'pending',
        'type', 'new_order'
      ),
      'order:new:' || new_order_id::text || ':' || recipient.id::text
    );
  end loop;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    p_actor_id,
    'order.created',
    'orders',
    new_order_id,
    jsonb_build_object(
      'order_number', new_order_number,
      'client_request_id', p_client_request_id,
      'subtotal', subtotal_amount,
      'total',
      subtotal_amount
        + configured_delivery_fee
        + configured_handling_fee
    )
  );

  return jsonb_build_object(
    'order', public.order_payload(new_order_id),
    'idempotent', false
  );
end;
$$;

comment on function public.place_order_transaction_impl(
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) is
  'Owner-only authoritative order implementation. Wholesale effective pricing drives totals; every line is reserved, while only tracked snapshots consume availability.';

create or replace function public.transition_order_status_transaction(
  p_actor_id uuid,
  p_order_id uuid,
  p_status text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_role text;
  current_order public.orders%rowtype;
  reservation record;
  status_label text;
begin
  select p.role
  into actor_role
  from public.profiles p
  where p.id = p_actor_id
    and p.active
    and not p.must_change_password
    and p.role in ('admin', 'staff');

  if actor_role is null then
    raise exception using
      errcode = 'P0001',
      message = 'STAFF_AUTH_REQUIRED';
  end if;

  if p_status not in (
    'pending',
    'confirmed',
    'preparing',
    'ready',
    'delivered',
    'cancelled'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'INVALID_ORDER_STATUS';
  end if;

  if length(coalesce(p_note, '')) > 1000 then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_NOTE_TOO_LONG';
  end if;

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

  if current_order.status = p_status then
    return jsonb_build_object(
      'order', public.order_payload(current_order.id)
        || jsonb_build_object(
          'status_history',
          public.order_status_history_payload(current_order.id)
        ),
      'idempotent', true
    );
  end if;

  if not (
    (
      current_order.status = 'pending'
      and p_status in ('confirmed', 'cancelled')
    )
    or (
      current_order.status = 'confirmed'
      and p_status in ('preparing', 'cancelled')
    )
    or (
      current_order.status = 'preparing'
      and p_status in ('ready', 'cancelled')
    )
    or (
      current_order.status = 'ready'
      and p_status in ('delivered', 'cancelled')
    )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'INVALID_STATUS_TRANSITION',
      detail = current_order.status || ' -> ' || p_status;
  end if;

  if p_status = 'delivered' then
    for reservation in
      select
        r.id,
        r.product_id,
        r.quantity,
        r.order_item_id,
        oi.stock_tracking_enabled_snapshot
      from public.inventory_reservations r
      join public.order_items oi
        on oi.id = r.order_item_id
        and oi.order_id = r.order_id
        and oi.product_id = r.product_id
        and oi.quantity = r.quantity
      where r.order_id = current_order.id
        and r.status = 'active'
      order by r.product_id, r.order_item_id
    loop
      if reservation.stock_tracking_enabled_snapshot then
        perform 1
        from public.products p
        where p.id = reservation.product_id
        for update;

        if (
          select p.stock_quantity
          from public.products p
          where p.id = reservation.product_id
        ) < reservation.quantity then
          raise exception using
            errcode = 'P0001',
            message = 'INSUFFICIENT_STOCK_AT_DELIVERY',
            detail = reservation.product_id::text;
        end if;

        update public.products
        set stock_quantity = stock_quantity - reservation.quantity
        where id = reservation.product_id;

        insert into public.inventory_movements (
          product_id,
          movement_type,
          quantity,
          note,
          created_by,
          order_id,
          order_item_id
        )
        values (
          reservation.product_id,
          'sale',
          -reservation.quantity,
          'خصم مخزون عند تسليم الطلب ' || current_order.order_number,
          p_actor_id,
          current_order.id,
          reservation.order_item_id
        );
      end if;

      update public.inventory_reservations
      set
        status = 'fulfilled',
        fulfilled_at = now()
      where id = reservation.id;
    end loop;
  elsif p_status = 'cancelled' then
    update public.inventory_reservations
    set
      status = 'released',
      released_at = now()
    where order_id = current_order.id
      and status = 'active';
  end if;

  update public.orders
  set
    status = p_status,
    admin_note = case
      when nullif(trim(p_note), '') is not null then trim(p_note)
      else admin_note
    end
  where id = current_order.id;

  insert into public.order_status_history (
    order_id,
    from_status,
    to_status,
    note,
    changed_by,
    changed_by_role
  )
  values (
    current_order.id,
    current_order.status,
    p_status,
    coalesce(trim(p_note), ''),
    p_actor_id,
    actor_role
  );

  status_label := case p_status
    when 'confirmed' then 'تم تأكيد طلبك'
    when 'preparing' then 'طلبك قيد التجهيز'
    when 'ready' then 'طلبك جاهز'
    when 'delivered' then 'تم تسليم طلبك'
    when 'cancelled' then 'تم إلغاء طلبك'
    else 'تم تحديث طلبك'
  end;

  if current_order.customer_profile_id is not null then
    perform public.enqueue_notification(
      current_order.customer_profile_id,
      'customer',
      'order_status_changed',
      status_label,
      'حالة الطلب ' || current_order.order_number
        || ' أصبحت: ' || status_label,
      jsonb_build_object(
        'order_id', current_order.id,
        'order_number', current_order.order_number,
        'status', p_status,
        'previous_status', current_order.status,
        'type', 'order_status_changed'
      ),
      'order:status:' || current_order.id::text || ':' || p_status
    );
  end if;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    p_actor_id,
    'order.status_changed',
    'orders',
    current_order.id,
    jsonb_build_object(
      'from_status', current_order.status,
      'to_status', p_status,
      'note', coalesce(trim(p_note), '')
    )
  );

  return jsonb_build_object(
    'order', public.order_payload(current_order.id)
      || jsonb_build_object(
        'status_history',
        public.order_status_history_payload(current_order.id)
      ),
    'idempotent', false
  );
end;
$$;

comment on function public.transition_order_status_transaction(
  uuid,
  uuid,
  text,
  text
) is
  'Authoritative staff transition. Delivery fulfills every reservation but deducts stock and records movements only for tracked order-line snapshots.';

create or replace function public.enforce_order_reservation_integrity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  expected_reservation_status text;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  expected_reservation_status := case
    when new.status in ('confirmed', 'preparing', 'ready') then 'active'
    when new.status = 'delivered' then 'fulfilled'
    else null
  end;

  if expected_reservation_status is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.order_items oi
    where oi.order_id = new.id
  ) or exists (
    select 1
    from public.order_items oi
    left join public.inventory_reservations r
      on r.order_item_id = oi.id
      and r.order_id = oi.order_id
      and r.product_id = oi.product_id
      and r.quantity = oi.quantity
      and r.status = expected_reservation_status
    where oi.order_id = new.id
    group by oi.id, oi.quantity
    having count(r.id) <> 1
      or coalesce(sum(r.quantity), 0) <> oi.quantity
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_RESERVATION_INCOMPLETE',
      detail = new.id::text;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_order_reservation_integrity()
  from public, anon, authenticated, service_role;

drop trigger if exists enforce_order_reservation_integrity
  on public.orders;
create trigger enforce_order_reservation_integrity
before update of status on public.orders
for each row
execute function public.enforce_order_reservation_integrity();

comment on function public.enforce_order_reservation_integrity() is
  'Requires exactly one correctly-sized reservation per order line, including non-stock-tracked lines.';

create or replace function public.enforce_reserved_stock_floor()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_stock integer;
  active_tracked_reserved integer;
begin
  select p.stock_quantity
  into current_stock
  from public.products p
  where p.id = new.id;

  if current_stock is null then
    return new;
  end if;

  select coalesce(sum(r.quantity), 0)::integer
  into active_tracked_reserved
  from public.inventory_reservations r
  join public.order_items oi
    on oi.id = r.order_item_id
    and oi.order_id = r.order_id
    and oi.product_id = r.product_id
    and oi.quantity = r.quantity
  where r.product_id = new.id
    and r.status = 'active'
    and oi.stock_tracking_enabled_snapshot;

  if current_stock < active_tracked_reserved then
    raise exception using
      errcode = 'P0001',
      message = 'STOCK_BELOW_ACTIVE_RESERVATIONS',
      detail = jsonb_build_object(
        'product_id', new.id,
        'stock_quantity', current_stock,
        'active_tracked_reserved', active_tracked_reserved
      )::text;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_reserved_stock_floor()
  from public, anon, authenticated, service_role;

drop trigger if exists enforce_reserved_stock_floor
  on public.products;
create constraint trigger enforce_reserved_stock_floor
after update on public.products
deferrable initially deferred
for each row
execute function public.enforce_reserved_stock_floor();

comment on function public.enforce_reserved_stock_floor() is
  'Prevents product stock from falling below active reservations whose order-line snapshots are stock tracked.';

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
      p.stock_tracking_enabled,
      case
        when p.stock_tracking_enabled then greatest(
          p.stock_quantity - coalesce(
            sum(r.quantity) filter (
              where r.status = 'active'
                and oi.stock_tracking_enabled_snapshot
            ),
            0
          ),
          0
        )::integer
        else null
      end as available_quantity
    from public.products p
    left join public.inventory_reservations r
      on r.product_id = p.id
      and r.status = 'active'
    left join public.order_items oi
      on oi.id = r.order_item_id
      and oi.order_id = r.order_id
      and oi.product_id = r.product_id
      and oi.quantity = r.quantity
    where p.active
      and p.archived_at is null
    group by
      p.id,
      p.name,
      p.sku,
      p.stock_tracking_enabled,
      p.stock_quantity
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
    where stock_tracking_enabled
      and available_quantity between 1 and 10
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
        where stock_tracking_enabled
          and available_quantity between 1 and 10
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
            ) = date_trunc(
              'month',
              timezone('Africa/Tripoli', now())
            )
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
      p.stock_tracking_enabled,
      case
        when p.stock_tracking_enabled then greatest(
          p.stock_quantity - coalesce(
            sum(r.quantity) filter (
              where r.status = 'active'
                and oi.stock_tracking_enabled_snapshot
            ),
            0
          ),
          0
        )::integer
        else null
      end as available_quantity
    from public.products p
    left join public.inventory_reservations r
      on r.product_id = p.id
      and r.status = 'active'
    left join public.order_items oi
      on oi.id = r.order_item_id
      and oi.order_id = r.order_id
      and oi.product_id = r.product_id
      and oi.quantity = r.quantity
    where p.active
      and p.archived_at is null
    group by
      p.id,
      p.name,
      p.sku,
      p.stock_tracking_enabled,
      p.stock_quantity
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
    where stock_tracking_enabled
      and available_quantity between 0 and 10
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

revoke all on function public.order_payload(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.place_order_transaction_impl(
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) from public, anon, authenticated, service_role;
revoke all on function public.place_order_transaction(
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) from public, anon, authenticated, service_role;
revoke all on function public.transition_order_status_transaction(
  uuid,
  uuid,
  text,
  text
) from public, anon, authenticated, service_role;
revoke all on function public.admin_dashboard_snapshot()
  from public, anon, authenticated, service_role;
revoke all on function public.admin_operational_report(
  timestamptz,
  timestamptz
) from public, anon, authenticated, service_role;

grant execute on function public.place_order_transaction(
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) to service_role;
grant execute on function public.transition_order_status_transaction(
  uuid,
  uuid,
  text,
  text
) to service_role;
grant execute on function public.admin_dashboard_snapshot()
  to authenticated;
grant execute on function public.admin_operational_report(
  timestamptz,
  timestamptz
) to authenticated;

comment on function public.admin_dashboard_snapshot() is
  'Bounded staff/admin dashboard metrics; low-stock data excludes untracked products and untracked order-line reservations.';
comment on function public.admin_operational_report(
  timestamptz,
  timestamptz
) is
  'Admin-only operational aggregates; inventory warnings exclude untracked products and untracked order-line reservations.';

notify pgrst, 'reload schema';

commit;
