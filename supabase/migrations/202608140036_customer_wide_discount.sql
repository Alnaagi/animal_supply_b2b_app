-- Replace group/product-specific runtime pricing with one audited,
-- customer-wide percentage discount applied to every product base price.
-- Legacy pricing tables remain intact for rollback/data review, but no runtime
-- catalog, bootstrap, customer-update, or order-pricing function consults them.

begin;

alter table public.business_customers
  add column if not exists discount_percent numeric(5,2);

update public.business_customers
set discount_percent = 0
where discount_percent is null;

alter table public.business_customers
  alter column discount_percent set default 0,
  alter column discount_percent set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'business_customers_discount_percent_range'
      and conrelid = 'public.business_customers'::regclass
  ) then
    alter table public.business_customers
      add constraint business_customers_discount_percent_range
      check (discount_percent >= 0 and discount_percent < 100)
      not valid;
  end if;
end
$$;

alter table public.business_customers
  validate constraint business_customers_discount_percent_range;

comment on column public.business_customers.discount_percent is
  'Customer-wide percentage discount applied to every positive products.base_price; values are from 0 through 99.99.';

create or replace function public.apply_customer_discount(
  p_base_price numeric,
  p_discount_percent numeric
)
returns numeric
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select case
    when p_base_price > 0 then greatest(
      round(
        p_base_price
          * (100 - coalesce(p_discount_percent, 0))
          / 100,
        2
      ),
      0.01::numeric
    )
    else p_base_price
  end
$$;

revoke all on function public.apply_customer_discount(numeric, numeric)
  from public, anon, authenticated, service_role;
grant execute on function public.apply_customer_discount(numeric, numeric)
  to authenticated, service_role;

comment on function public.apply_customer_discount(numeric, numeric) is
  'Applies a customer-wide percentage to a base price, rounds to two decimals, and keeps every positive base price at or above 0.01.';

create or replace function public.effective_product_price(
  p_customer_id uuid,
  p_product_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.apply_customer_discount(
    product.base_price,
    customer.discount_percent
  )
  from public.business_customers customer
  join public.products product
    on product.id = p_product_id
  where customer.id = p_customer_id
$$;

revoke all on function public.effective_product_price(uuid, uuid)
  from public, anon, authenticated, service_role;

comment on function public.effective_product_price(uuid, uuid) is
  'Service-internal authoritative customer price derived only from products.base_price and business_customers.discount_percent.';

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
  with actor_base as (
    select
      public.current_role() as role,
      public.current_customer_id() as customer_id
  ),
  actor as (
    select
      actor_base.role,
      actor_base.customer_id,
      coalesce(customer.discount_percent, 0) as customer_discount_percent
    from actor_base
    left join public.business_customers customer
      on customer.id = actor_base.customer_id
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
      when actor.role = 'customer' then public.apply_customer_discount(
        p.base_price,
        actor.customer_discount_percent
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
  'Returns caller-visible products with customer-wide discounted effective prices, tracked nullable availability, stock-count visibility, and customer out-of-stock hiding.';

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
  with actor_base as (
    select
      public.current_role() as role,
      public.current_customer_id() as customer_id
  ),
  actor as (
    select
      actor_base.role,
      actor_base.customer_id,
      coalesce(customer.discount_percent, 0) as customer_discount_percent
    from actor_base
    left join public.business_customers customer
      on customer.id = actor_base.customer_id
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
        when actor.role = 'customer' then public.apply_customer_discount(
          p.base_price,
          actor.customer_discount_percent
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
  'Returns one RLS-scoped catalog page with customer-wide discounted pricing and deterministic newest, oldest, name, price, or available-stock sorting.';

create or replace function public.bootstrap_current_account()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles%rowtype;
  v_customer public.business_customers%rowtype;
  v_can_use_app boolean := false;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;

  select p.*
  into v_profile
  from public.profiles p
  where p.id = auth.uid();

  if not found then
    raise exception using errcode = 'P0001', message = 'PROFILE_REQUIRED';
  end if;

  if v_profile.role not in ('admin', 'staff', 'customer') then
    raise exception using errcode = 'P0001', message = 'ROLE_INVALID';
  end if;

  if v_profile.role = 'customer' then
    select c.*
    into v_customer
    from public.business_customers c
    where c.profile_id = v_profile.id;
  end if;

  v_can_use_app :=
    v_profile.active
    and not v_profile.must_change_password
    and (
      v_profile.role in ('admin', 'staff')
      or (
        v_profile.role = 'customer'
        and v_customer.id is not null
        and v_customer.account_status = 'active'
        and v_customer.archived_at is null
      )
    );

  return jsonb_strip_nulls(
    jsonb_build_object(
      'id', v_profile.id,
      'username', v_profile.username,
      'role', v_profile.role,
      'active', v_profile.active,
      'must_change_password', v_profile.must_change_password,
      'full_name', case when v_can_use_app then v_profile.full_name end,
      'phone', case when v_can_use_app then v_profile.phone end,
      'customer', case
        when v_profile.role <> 'customer' or v_customer.id is null then null
        else jsonb_strip_nulls(
          jsonb_build_object(
            'id', v_customer.id,
            'account_status', v_customer.account_status,
            'business_name',
              case when v_can_use_app then v_customer.business_name end,
            'contact_person',
              case when v_can_use_app then v_customer.contact_person end,
            'phone', case when v_can_use_app then v_customer.phone end,
            'city', case when v_can_use_app then v_customer.city end,
            'area', case when v_can_use_app then v_customer.area end,
            'address', case when v_can_use_app then v_customer.address end,
            'credit_limit',
              case when v_can_use_app then v_customer.credit_limit end,
            'outstanding_balance',
              case when v_can_use_app then v_customer.outstanding_balance end,
            'discount_percent',
              case when v_can_use_app then v_customer.discount_percent end
          )
        )
      end
    )
  );
end;
$$;

revoke all on function public.bootstrap_current_account()
  from public, anon, authenticated, service_role;
grant execute on function public.bootstrap_current_account()
  to authenticated;

comment on function public.bootstrap_current_account() is
  'Returns the current account bootstrap payload and exposes an active customer only to its own customer-wide discount percentage.';

create or replace function public.admin_update_business_customer_v2(
  p_actor_id uuid,
  p_customer_id uuid,
  p_business_name text,
  p_contact_person text,
  p_phone text,
  p_city text,
  p_area text,
  p_address text,
  p_customer_discount_percent numeric,
  p_account_status text,
  p_credit_limit numeric,
  p_outstanding_balance numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_role text;
  v_target_profile_role text;
  v_target_profile_active boolean;
  v_target_username text;
  v_before public.business_customers%rowtype;
  v_after public.business_customers%rowtype;
  v_effective_discount_percent numeric(5,2);
  v_changed_fields jsonb := '[]'::jsonb;
begin
  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = p_actor_id
    and p.active
    and not p.must_change_password
    and p.role in ('admin', 'staff');

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'STAFF_AUTH_REQUIRED';
  end if;

  select c.*
  into v_before
  from public.business_customers c
  where c.id = p_customer_id
  for update;

  if not found or v_before.profile_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_NOT_FOUND';
  end if;

  v_effective_discount_percent := coalesce(
    p_customer_discount_percent,
    v_before.discount_percent,
    0
  );

  select p.role, p.active, p.username
  into v_target_profile_role, v_target_profile_active, v_target_username
  from public.profiles p
  where p.id = v_before.profile_id;

  if not found or v_target_profile_role <> 'customer' then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_TARGET_REQUIRED';
  end if;

  if p_business_name is null
    or char_length(btrim(p_business_name)) = 0
    or char_length(btrim(p_business_name)) > 160
  then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_UPDATE_INVALID';
  end if;

  if p_account_status is null
    or p_account_status not in ('active', 'suspended', 'archived')
    or v_effective_discount_percent < 0
    or v_effective_discount_percent >= 100
    or (
      p_customer_discount_percent is not null
      and round(p_customer_discount_percent, 2)
        <> p_customer_discount_percent
    )
    or p_credit_limit is null
    or p_credit_limit < 0
    or p_credit_limit > 9999999999.99
    or p_outstanding_balance is null
    or p_outstanding_balance < 0
    or p_outstanding_balance > 9999999999.99
    or char_length(coalesce(p_contact_person, '')) > 160
    or char_length(coalesce(p_phone, '')) > 32
    or char_length(coalesce(p_city, '')) > 100
    or char_length(coalesce(p_area, '')) > 120
    or char_length(coalesce(p_address, '')) > 500
  then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_UPDATE_INVALID';
  end if;

  if v_before.business_name is distinct from btrim(p_business_name) then
    v_changed_fields := v_changed_fields || '"business_name"'::jsonb;
  end if;
  if v_before.contact_person is distinct from nullif(btrim(p_contact_person), '') then
    v_changed_fields := v_changed_fields || '"contact_person"'::jsonb;
  end if;
  if v_before.phone is distinct from nullif(btrim(p_phone), '') then
    v_changed_fields := v_changed_fields || '"phone"'::jsonb;
  end if;
  if v_before.city is distinct from nullif(btrim(p_city), '') then
    v_changed_fields := v_changed_fields || '"city"'::jsonb;
  end if;
  if v_before.area is distinct from nullif(btrim(p_area), '') then
    v_changed_fields := v_changed_fields || '"area"'::jsonb;
  end if;
  if v_before.address is distinct from nullif(btrim(p_address), '') then
    v_changed_fields := v_changed_fields || '"address"'::jsonb;
  end if;
  if v_before.discount_percent is distinct from v_effective_discount_percent then
    v_changed_fields := v_changed_fields || '"discount_percent"'::jsonb;
  end if;
  if v_before.account_status is distinct from p_account_status then
    v_changed_fields := v_changed_fields || '"account_status"'::jsonb;
  end if;
  if v_before.credit_limit is distinct from p_credit_limit then
    v_changed_fields := v_changed_fields || '"credit_limit"'::jsonb;
  end if;
  if v_before.outstanding_balance is distinct from p_outstanding_balance then
    v_changed_fields := v_changed_fields || '"outstanding_balance"'::jsonb;
  end if;

  update public.business_customers
  set
    business_name = btrim(p_business_name),
    contact_person = nullif(btrim(p_contact_person), ''),
    phone = nullif(btrim(p_phone), ''),
    city = nullif(btrim(p_city), ''),
    area = nullif(btrim(p_area), ''),
    address = nullif(btrim(p_address), ''),
    discount_percent = v_effective_discount_percent,
    account_status = p_account_status,
    credit_limit = p_credit_limit,
    outstanding_balance = p_outstanding_balance,
    archived_at = case
      when p_account_status = 'archived'
        then coalesce(archived_at, now())
      else null
    end
  where id = p_customer_id
    and profile_id = v_before.profile_id
  returning *
  into v_after;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_UPDATE_CONFLICT';
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
    'customer.updated',
    'business_customers',
    v_after.id,
    jsonb_build_object(
      'actor_role', v_actor_role,
      'target_profile_id', v_after.profile_id,
      'target_profile_active', v_target_profile_active,
      'changed_fields', v_changed_fields,
      'discount_percent', jsonb_build_object(
        'from', v_before.discount_percent,
        'to', v_after.discount_percent
      ),
      'account_status', jsonb_build_object(
        'from', v_before.account_status,
        'to', v_after.account_status
      ),
      'credit_limit', jsonb_build_object(
        'from', v_before.credit_limit,
        'to', v_after.credit_limit
      ),
      'outstanding_balance', jsonb_build_object(
        'from', v_before.outstanding_balance,
        'to', v_after.outstanding_balance
      )
    )
  );

  return to_jsonb(v_after) || jsonb_build_object(
    'profiles', jsonb_build_object(
      'username', coalesce(v_target_username, '')
    )
  );
end;
$$;

revoke all on function public.admin_update_business_customer_v2(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  numeric,
  numeric
) from public, anon, authenticated, service_role;
grant execute on function public.admin_update_business_customer_v2(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  numeric,
  numeric
) to service_role;

comment on function public.admin_update_business_customer_v2(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  numeric,
  numeric
) is
  'Service-only audited staff/admin customer update using one customer-wide discount percentage.';

create or replace function public.admin_update_business_customer(
  p_actor_id uuid,
  p_customer_id uuid,
  p_business_name text,
  p_contact_person text,
  p_phone text,
  p_city text,
  p_area text,
  p_address text,
  p_price_group_id uuid,
  p_account_status text,
  p_credit_limit numeric,
  p_outstanding_balance numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_discount_percent numeric(5,2);
begin
  -- The legacy price-group argument is intentionally ignored. Locking the row
  -- before forwarding prevents an old caller from overwriting a concurrent
  -- discount update with a stale value.
  select customer.discount_percent
  into v_discount_percent
  from public.business_customers customer
  where customer.id = p_customer_id
  for update;

  return public.admin_update_business_customer_v2(
    p_actor_id,
    p_customer_id,
    p_business_name,
    p_contact_person,
    p_phone,
    p_city,
    p_area,
    p_address,
    coalesce(v_discount_percent, 0),
    p_account_status,
    p_credit_limit,
    p_outstanding_balance
  );
end;
$$;

revoke all on function public.admin_update_business_customer(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  numeric,
  numeric
) from public, anon, authenticated, service_role;
grant execute on function public.admin_update_business_customer(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  numeric,
  numeric
) to service_role;

comment on function public.admin_update_business_customer(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  numeric,
  numeric
) is
  'Compatibility wrapper for the former price-group contract; it ignores the legacy group argument and preserves the current customer-wide discount.';

notify pgrst, 'reload schema';

commit;
