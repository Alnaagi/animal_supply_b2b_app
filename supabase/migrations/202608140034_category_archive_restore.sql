-- Archive and restore categories as one audited transaction.
--
-- Products archived independently are deliberately left untouched. The
-- archived_by_category_id marker identifies only products archived by the
-- category operation so a later category restore cannot revive unrelated
-- product archives.

begin;

alter table public.categories
  add column if not exists active_before_category_archive boolean;

alter table public.categories
  add column if not exists category_archive_operation_id uuid;

alter table public.products
  add column if not exists archived_by_category_id uuid;

alter table public.products
  add column if not exists active_before_category_archive boolean;

alter table public.products
  add column if not exists category_archive_operation_id uuid;

-- Normalize any legacy/manual category archive state before enforcing the new
-- reversible provenance contract. Existing archived products are deliberately
-- not assumed to have been archived by their category.
update public.categories c
set
  active_before_category_archive = coalesce(
    c.active_before_category_archive,
    c.active
  ),
  category_archive_operation_id = coalesce(
    c.category_archive_operation_id,
    gen_random_uuid()
  ),
  active = false
where c.archived_at is not null;

update public.categories c
set
  active_before_category_archive = null,
  category_archive_operation_id = null
where c.archived_at is null
  and (
    c.active_before_category_archive is not null
    or c.category_archive_operation_id is not null
  );

update public.products p
set
  archived_by_category_id = null,
  active_before_category_archive = null,
  category_archive_operation_id = null
where p.archived_by_category_id is null
  and (
    p.active_before_category_archive is not null
    or p.category_archive_operation_id is not null
  );

update public.products p
set
  archived_by_category_id = null,
  active_before_category_archive = null,
  category_archive_operation_id = null
where p.archived_by_category_id is not null
  and not exists (
    select 1
    from public.categories c
    where c.id = p.archived_by_category_id
      and c.id = p.category_id
      and c.archived_at is not null
  );

update public.products p
set
  active = false,
  archived_at = coalesce(p.archived_at, c.archived_at),
  active_before_category_archive = coalesce(
    p.active_before_category_archive,
    p.active
  ),
  category_archive_operation_id = c.category_archive_operation_id
from public.categories c
where p.archived_by_category_id = c.id
  and p.category_id = c.id
  and c.archived_at is not null;

update public.products p
set
  active = false,
  archived_at = c.archived_at,
  archived_by_category_id = c.id,
  active_before_category_archive = p.active,
  category_archive_operation_id = c.category_archive_operation_id
from public.categories c
where p.category_id = c.id
  and c.archived_at is not null
  and p.archived_at is null;

alter table public.products
  drop constraint if exists products_archived_by_category_id_fkey;

alter table public.products
  add constraint products_archived_by_category_id_fkey
  foreign key (archived_by_category_id)
  references public.categories(id)
  on delete restrict
  not valid;

alter table public.products
  validate constraint products_archived_by_category_id_fkey;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.categories'::regclass
      and conname = 'categories_archive_provenance_consistent'
  ) then
    alter table public.categories
      add constraint categories_archive_provenance_consistent
      check (
        (
          archived_at is null
          and active_before_category_archive is null
          and category_archive_operation_id is null
        )
        or (
          archived_at is not null
          and not active
          and active_before_category_archive is not null
          and category_archive_operation_id is not null
        )
      );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.products'::regclass
      and conname = 'products_category_archive_provenance_consistent'
  ) then
    alter table public.products
      add constraint products_category_archive_provenance_consistent
      check (
        (
          archived_by_category_id is null
          and active_before_category_archive is null
          and category_archive_operation_id is null
        )
        or (
          archived_by_category_id is not null
          and category_id is not null
          and category_id = archived_by_category_id
          and archived_at is not null
          and not active
          and active_before_category_archive is not null
          and category_archive_operation_id is not null
        )
      );
  end if;
end
$$;

create index if not exists idx_products_archived_by_category
  on public.products(
    archived_by_category_id,
    category_archive_operation_id
  )
  where archived_by_category_id is not null;

comment on column public.categories.active_before_category_archive is
  'Category visibility captured immediately before an audited category archive and cleared when that archive is restored.';
comment on column public.categories.category_archive_operation_id is
  'Opaque identifier for the currently active category archive operation.';
comment on column public.products.archived_by_category_id is
  'Set only when a category archive operation archived the product; used to restore only that operation''s products.';
comment on column public.products.active_before_category_archive is
  'Previous product visibility saved by a category archive operation and cleared when that operation is restored.';
comment on column public.products.category_archive_operation_id is
  'Matches the category archive operation that changed this product; later independent archive-state changes clear it.';

create or replace function public.enforce_category_archive_write_boundary()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      if new.archived_at is not null
        or new.active_before_category_archive is not null
        or new.category_archive_operation_id is not null
      then
        raise exception 'CATEGORY_ARCHIVE_PROVENANCE_SERVER_MANAGED'
          using errcode = '42501';
      end if;
    elsif new.archived_at is distinct from old.archived_at
      or new.active_before_category_archive
        is distinct from old.active_before_category_archive
      or new.category_archive_operation_id
        is distinct from old.category_archive_operation_id
    then
      raise exception 'CATEGORY_ARCHIVE_PROVENANCE_SERVER_MANAGED'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_category_archive_write_boundary
  on public.categories;
create trigger enforce_category_archive_write_boundary
before insert or update on public.categories
for each row
execute function public.enforce_category_archive_write_boundary();

create or replace function public.enforce_product_category_archive_state()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_category_archived_at timestamptz;
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      if new.archived_by_category_id is not null
        or new.active_before_category_archive is not null
        or new.category_archive_operation_id is not null
      then
        raise exception 'CATEGORY_ARCHIVE_PROVENANCE_SERVER_MANAGED'
          using errcode = '42501';
      end if;
    else
      if new.archived_by_category_id
          is distinct from old.archived_by_category_id
        or new.active_before_category_archive
          is distinct from old.active_before_category_archive
        or new.category_archive_operation_id
          is distinct from old.category_archive_operation_id
      then
        raise exception 'CATEGORY_ARCHIVE_PROVENANCE_SERVER_MANAGED'
          using errcode = '42501';
      end if;

      if old.archived_by_category_id is not null
        and (
          new.category_id is distinct from old.category_id
          or new.active is distinct from old.active
          or new.archived_at is distinct from old.archived_at
        )
      then
        new.archived_by_category_id = null;
        new.active_before_category_archive = null;
        new.category_archive_operation_id = null;
      end if;
    end if;
  end if;

  if new.category_id is not null
    and new.active
    and new.archived_at is null
  then
    select c.archived_at
    into v_category_archived_at
    from public.categories c
    where c.id = new.category_id
    for key share;

    if found and v_category_archived_at is not null then
      raise exception 'PRODUCT_CATEGORY_ARCHIVED'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_product_category_archive_state
  on public.products;
create trigger enforce_product_category_archive_state
before insert or update on public.products
for each row
execute function public.enforce_product_category_archive_state();

revoke all on function public.enforce_category_archive_write_boundary()
  from public, anon, authenticated;
revoke all on function public.enforce_product_category_archive_state()
  from public, anon, authenticated;

create or replace function public.admin_archive_category(
  p_category_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid := auth.uid();
  v_category public.categories%rowtype;
  v_archived_at timestamptz;
  v_archive_operation_id uuid;
  v_archived_product_count integer := 0;
begin
  if not public.is_staff_or_admin() then
    raise exception 'STAFF_OR_ADMIN_REQUIRED'
      using errcode = '42501';
  end if;

  if p_category_id is null then
    raise exception 'CATEGORY_ID_REQUIRED'
      using errcode = '22023';
  end if;

  select c.*
  into v_category
  from public.categories c
  where c.id = p_category_id
  for update;

  if not found then
    raise exception 'CATEGORY_NOT_FOUND'
      using errcode = 'P0001';
  end if;

  if v_category.archived_at is not null then
    return jsonb_build_object(
      'category_id', p_category_id,
      'category_name', v_category.name,
      'archived_product_count', 0,
      'archived_at', v_category.archived_at,
      'changed', false
    );
  end if;

  v_archived_at := statement_timestamp();
  v_archive_operation_id := gen_random_uuid();

  update public.categories c
  set
    active = false,
    archived_at = v_archived_at,
    active_before_category_archive = v_category.active,
    category_archive_operation_id = v_archive_operation_id
  where c.id = p_category_id;

  update public.products p
  set
    active = false,
    archived_at = v_archived_at,
    archived_by_category_id = p_category_id,
    active_before_category_archive = p.active,
    category_archive_operation_id = v_archive_operation_id
  where p.category_id = p_category_id
    and p.archived_at is null;

  get diagnostics v_archived_product_count = row_count;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    v_actor_id,
    'category.archived',
    'categories',
    p_category_id,
    jsonb_build_object(
      'category_name', v_category.name,
      'archived_product_count', v_archived_product_count,
      'archived_at', v_archived_at,
      'active_before_archive', v_category.active,
      'archive_operation_id', v_archive_operation_id
    )
  );

  return jsonb_build_object(
    'category_id', p_category_id,
    'category_name', v_category.name,
    'archived_product_count', v_archived_product_count,
    'archived_at', v_archived_at,
    'changed', true
  );
end;
$$;

create or replace function public.admin_restore_category(
  p_category_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid := auth.uid();
  v_category public.categories%rowtype;
  v_restored_product_count integer := 0;
  v_detached_product_count integer := 0;
begin
  if not public.is_staff_or_admin() then
    raise exception 'STAFF_OR_ADMIN_REQUIRED'
      using errcode = '42501';
  end if;

  if p_category_id is null then
    raise exception 'CATEGORY_ID_REQUIRED'
      using errcode = '22023';
  end if;

  select c.*
  into v_category
  from public.categories c
  where c.id = p_category_id
  for update;

  if not found then
    raise exception 'CATEGORY_NOT_FOUND'
      using errcode = 'P0001';
  end if;

  if v_category.archived_at is null then
    return jsonb_build_object(
      'category_id', p_category_id,
      'category_name', v_category.name,
      'restored_product_count', 0,
      'detached_product_count', 0,
      'changed', false
    );
  end if;

  update public.categories c
  set
    active = v_category.active_before_category_archive,
    archived_at = null,
    active_before_category_archive = null,
    category_archive_operation_id = null
  where c.id = p_category_id;

  update public.products p
  set
    active = p.active_before_category_archive,
    archived_at = null,
    archived_by_category_id = null,
    active_before_category_archive = null,
    category_archive_operation_id = null
  where p.archived_by_category_id = p_category_id
    and p.category_archive_operation_id =
      v_category.category_archive_operation_id
    and p.category_id = p_category_id
    and p.archived_at = v_category.archived_at;

  get diagnostics v_restored_product_count = row_count;

  update public.products p
  set
    archived_by_category_id = null,
    active_before_category_archive = null,
    category_archive_operation_id = null
  where p.archived_by_category_id = p_category_id
    and p.category_archive_operation_id =
      v_category.category_archive_operation_id;

  get diagnostics v_detached_product_count = row_count;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    v_actor_id,
    'category.restored',
    'categories',
    p_category_id,
    jsonb_build_object(
      'category_name', v_category.name,
      'restored_product_count', v_restored_product_count,
      'detached_product_count', v_detached_product_count,
      'active_after_restore', v_category.active_before_category_archive,
      'archive_operation_id', v_category.category_archive_operation_id
    )
  );

  return jsonb_build_object(
    'category_id', p_category_id,
    'category_name', v_category.name,
    'restored_product_count', v_restored_product_count,
    'detached_product_count', v_detached_product_count,
    'changed', true
  );
end;
$$;

-- Keep ordinary staff/admin catalog edits available while forcing destructive
-- category/product removal through reversible archive workflows.
drop policy if exists "categories staff manage" on public.categories;
drop policy if exists "categories staff insert" on public.categories;
drop policy if exists "categories staff update" on public.categories;
drop policy if exists "products staff manage" on public.products;
drop policy if exists "products staff insert" on public.products;
drop policy if exists "products staff update" on public.products;

create policy "categories staff insert"
on public.categories
for insert
with check (public.is_staff_or_admin());

create policy "categories staff update"
on public.categories
for update
using (public.is_staff_or_admin())
with check (public.is_staff_or_admin());

create policy "products staff insert"
on public.products
for insert
with check (public.is_staff_or_admin());

create policy "products staff update"
on public.products
for update
using (public.is_staff_or_admin())
with check (public.is_staff_or_admin());

drop policy if exists "categories active readable" on public.categories;
create policy "categories active readable"
on public.categories
for select
using (
  public.is_active_actor()
  and (
    public.is_staff_or_admin()
    or (active and archived_at is null)
  )
);

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
        category_id is null
        or exists (
          select 1
          from public.categories c
          where c.id = category_id
            and c.active
            and c.archived_at is null
        )
      )
    )
  )
);

revoke delete on public.categories, public.products
  from public, anon, authenticated;
grant delete on public.categories, public.products
  to service_role;

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

revoke all on function public.admin_archive_category(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_restore_category(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.admin_archive_category(uuid)
  to authenticated;
grant execute on function public.admin_restore_category(uuid)
  to authenticated;

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

comment on function public.admin_archive_category(uuid) is
  'Archives one category and all currently unarchived products assigned to it, recording which products belong to the reversible category operation.';
comment on function public.admin_restore_category(uuid) is
  'Restores one category and only products marked as archived by that category operation.';
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
  'Returns one RLS-scoped page with category-archive provenance for staff/admin rows and active-category defense for customer rows.';

notify pgrst, 'reload schema';

commit;
