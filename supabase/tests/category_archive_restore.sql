\set ON_ERROR_STOP on

-- Rollback-only verification for migration 202608140034.
--
-- Required psql variables:
--   admin_profile_id     active admin profile UUID
--   customer_profile_id  active customer profile UUID
--
-- Run against a local or staging database after applying migrations:
--
--   psql "$DATABASE_URL" \
--     -f supabase/tests/category_archive_restore.sql \
--     -v admin_profile_id=... \
--     -v customer_profile_id=...

begin;

select set_config(
  'test.admin_profile_id',
  :'admin_profile_id',
  true
);
select set_config(
  'test.customer_profile_id',
  :'customer_profile_id',
  true
);

do $$
begin
  if not has_function_privilege(
    'authenticated',
    'public.admin_archive_category(uuid)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated actors cannot execute category archive RPC';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.admin_restore_category(uuid)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated actors cannot execute category restore RPC';
  end if;

  if has_function_privilege(
    'anon',
    'public.admin_archive_category(uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.admin_restore_category(uuid)',
    'EXECUTE'
  ) then
    raise exception 'Anonymous actors can execute category archive RPCs';
  end if;

  if has_table_privilege(
    'authenticated',
    'public.categories',
    'DELETE'
  ) or has_table_privilege(
    'authenticated',
    'public.products',
    'DELETE'
  ) then
    raise exception 'Authenticated actors retain permanent catalog DELETE';
  end if;

  if not has_table_privilege(
    'service_role',
    'public.categories',
    'DELETE'
  ) or not has_table_privilege(
    'service_role',
    'public.products',
    'DELETE'
  ) then
    raise exception 'Service role catalog DELETE access was weakened';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.categories'::regclass
      and conname = 'categories_archive_provenance_consistent'
      and convalidated
  ) or not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.products'::regclass
      and conname = 'products_category_archive_provenance_consistent'
      and convalidated
  ) then
    raise exception 'Category archive provenance constraints are missing';
  end if;
end;
$$;

create temporary table category_archive_context (
  category_id uuid not null,
  inactive_category_id uuid not null,
  other_category_id uuid not null,
  active_product_id uuid not null,
  inactive_product_id uuid not null,
  later_independent_product_id uuid not null,
  reassigned_product_id uuid not null,
  independently_archived_product_id uuid not null
) on commit drop;

do $$
declare
  v_category_id uuid;
  v_inactive_category_id uuid;
  v_other_category_id uuid;
  v_active_product_id uuid;
  v_inactive_product_id uuid;
  v_later_independent_product_id uuid;
  v_reassigned_product_id uuid;
  v_independent_product_id uuid;
  v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
begin
  insert into public.categories (name, active, icon_key)
  values ('اختبار أرشفة تصنيف ' || v_suffix, true, 'category')
  returning id into v_category_id;

  insert into public.categories (name, active, icon_key)
  values ('اختبار تصنيف مخفي ' || v_suffix, false, 'category')
  returning id into v_inactive_category_id;

  insert into public.categories (name, active, icon_key)
  values ('اختبار تصنيف بديل ' || v_suffix, true, 'category')
  returning id into v_other_category_id;

  insert into public.products (
    category_id,
    name,
    sku,
    base_price,
    stock_quantity,
    min_order_quantity,
    active
  )
  values (
    v_category_id,
    'منتج نشط لأرشفة التصنيف',
    'CAT-ARCH-ACTIVE-' || v_suffix,
    10,
    5,
    1,
    true
  )
  returning id into v_active_product_id;

  insert into public.products (
    category_id,
    name,
    sku,
    base_price,
    stock_quantity,
    min_order_quantity,
    active
  )
  values (
    v_category_id,
    'منتج مخفي لأرشفة التصنيف',
    'CAT-ARCH-INACTIVE-' || v_suffix,
    11,
    5,
    1,
    false
  )
  returning id into v_inactive_product_id;

  insert into public.products (
    category_id,
    name,
    sku,
    base_price,
    stock_quantity,
    min_order_quantity,
    active
  )
  values (
    v_category_id,
    'منتج سيؤرشف لاحقاً بشكل مستقل',
    'CAT-ARCH-LATER-' || v_suffix,
    12,
    5,
    1,
    true
  )
  returning id into v_later_independent_product_id;

  insert into public.products (
    category_id,
    name,
    sku,
    base_price,
    stock_quantity,
    min_order_quantity,
    active
  )
  values (
    v_category_id,
    'منتج سيُنقل إلى تصنيف آخر',
    'CAT-ARCH-MOVED-' || v_suffix,
    13,
    5,
    1,
    true
  )
  returning id into v_reassigned_product_id;

  insert into public.products (
    category_id,
    name,
    sku,
    base_price,
    stock_quantity,
    min_order_quantity,
    active,
    archived_at
  )
  values (
    v_category_id,
    'منتج مؤرشف بشكل مستقل',
    'CAT-ARCH-INDEPENDENT-' || v_suffix,
    14,
    5,
    1,
    false,
    statement_timestamp() - interval '1 day'
  )
  returning id into v_independent_product_id;

  insert into category_archive_context (
    category_id,
    inactive_category_id,
    other_category_id,
    active_product_id,
    inactive_product_id,
    later_independent_product_id,
    reassigned_product_id,
    independently_archived_product_id
  )
  values (
    v_category_id,
    v_inactive_category_id,
    v_other_category_id,
    v_active_product_id,
    v_inactive_product_id,
    v_later_independent_product_id,
    v_reassigned_product_id,
    v_independent_product_id
  );
end;
$$;

grant select on category_archive_context to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'customer_profile_id',
  true
);

do $$
declare
  test category_archive_context%rowtype;
begin
  select * into test from category_archive_context;

  begin
    perform public.admin_archive_category(test.category_id);
    raise exception 'Customer unexpectedly archived a category';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.admin_restore_category(test.category_id);
    raise exception 'Customer unexpectedly restored a category';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'admin_profile_id',
  true
);

do $$
declare
  test category_archive_context%rowtype;
  archive_result jsonb;
  repeated_archive_result jsonb;
  restore_result jsonb;
  repeated_restore_result jsonb;
  inactive_archive_result jsonb;
  inactive_restore_result jsonb;
  page_result jsonb;
  customer_page_result jsonb;
  active_page_row jsonb;
  inactive_page_row jsonb;
  v_category_name text;
  v_archive_audit_count bigint;
  v_restore_audit_count bigint;
begin
  select * into test from category_archive_context;
  select c.name
  into v_category_name
  from public.categories c
  where c.id = test.category_id;

  archive_result := public.admin_archive_category(test.category_id);

  if coalesce(
    (archive_result->>'archived_product_count')::integer,
    -1
  ) <> 4 or (archive_result->>'changed')::boolean is not true then
    raise exception
      'Expected four category products to be archived once, got %',
      archive_result;
  end if;

  if not exists (
    select 1
    from public.categories c
    where c.id = test.category_id
      and not c.active
      and c.archived_at is not null
      and c.active_before_category_archive is true
      and c.category_archive_operation_id is not null
  ) then
    raise exception 'Category archive state was not persisted';
  end if;

  if (
    select count(*)
    from public.products p
    where p.id in (
      test.active_product_id,
      test.inactive_product_id,
      test.later_independent_product_id,
      test.reassigned_product_id
    )
      and not p.active
      and p.archived_at is not null
      and p.archived_by_category_id = test.category_id
      and p.category_archive_operation_id = (
        select c.category_archive_operation_id
        from public.categories c
        where c.id = test.category_id
      )
  ) <> 4 then
    raise exception 'Category products were not marked for reversible restore';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = test.active_product_id
      and p.active_before_category_archive is true
  ) or not exists (
    select 1
    from public.products p
    where p.id = test.inactive_product_id
      and p.active_before_category_archive is false
  ) then
    raise exception 'Category archive did not preserve product visibility';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = test.independently_archived_product_id
      and not p.active
      and p.archived_at is not null
      and p.archived_by_category_id is null
      and p.active_before_category_archive is null
      and p.category_archive_operation_id is null
  ) then
    raise exception 'Independent product archive was altered by category archive';
  end if;

  page_result := public.catalog_products_page(
    p_category => v_category_name,
    p_include_inactive => true,
    p_limit => 100
  );

  select item.value
  into active_page_row
  from jsonb_array_elements(page_result->'products') item(value)
  where item.value->>'id' = test.active_product_id::text;

  select item.value
  into inactive_page_row
  from jsonb_array_elements(page_result->'products') item(value)
  where item.value->>'id' = test.inactive_product_id::text;

  if active_page_row is null
    or not (active_page_row ? 'archived_by_category_id')
    or not (active_page_row ? 'active_before_category_archive')
    or active_page_row->>'archived_by_category_id' <>
      test.category_id::text
    or (active_page_row->>'active_before_category_archive')::boolean
      is distinct from true
    or inactive_page_row is null
    or (inactive_page_row->>'active_before_category_archive')::boolean
      is distinct from false
  then
    raise exception
      'Admin catalog page omitted category archive provenance: %',
      page_result;
  end if;

  select count(*)
  into v_archive_audit_count
  from public.audit_logs log
  where log.entity_table = 'categories'
    and log.entity_id = test.category_id
    and log.action = 'category.archived';

  if v_archive_audit_count <> 1 then
    raise exception 'Category archive audit event was not written exactly once';
  end if;

  repeated_archive_result :=
    public.admin_archive_category(test.category_id);
  if coalesce(
    (repeated_archive_result->>'archived_product_count')::integer,
    -1
  ) <> 0
    or (repeated_archive_result->>'changed')::boolean is not false
  then
    raise exception 'Repeated category archive was not idempotent';
  end if;

  select count(*)
  into v_archive_audit_count
  from public.audit_logs log
  where log.entity_table = 'categories'
    and log.entity_id = test.category_id
    and log.action = 'category.archived';

  if v_archive_audit_count <> 1 then
    raise exception 'Repeated category archive duplicated its audit event';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    current_setting('test.customer_profile_id'),
    true
  );
  customer_page_result := public.catalog_products_page(
    p_category => v_category_name,
    p_include_inactive => true,
    p_limit => 100
  );
  if jsonb_array_length(customer_page_result->'products') <> 0 then
    raise exception
      'Customer catalog exposed products from an archived category: %',
      customer_page_result;
  end if;
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('test.admin_profile_id'),
    true
  );

  begin
    insert into public.products (
      category_id,
      name,
      sku,
      base_price,
      stock_quantity,
      min_order_quantity,
      active
    )
    values (
      test.category_id,
      'منتج متأخر داخل تصنيف مؤرشف',
      'CAT-ARCH-LATE-INSERT-' ||
        substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
      15,
      5,
      1,
      true
    );
    raise exception 'Active product was inserted into an archived category';
  exception
    when check_violation then
      null;
  end;

  begin
    update public.products
    set archived_by_category_id = test.category_id
    where id = test.independently_archived_product_id;
    raise exception 'Authenticated actor changed archive provenance directly';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    update public.categories
    set
      active = false,
      archived_at = statement_timestamp(),
      active_before_category_archive = true,
      category_archive_operation_id = gen_random_uuid()
    where id = test.other_category_id;
    raise exception 'Authenticated actor changed category archive state directly';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    delete from public.products
    where id = test.independently_archived_product_id;
    raise exception 'Authenticated actor permanently deleted a product';
  exception
    when insufficient_privilege then
      null;
  end;

  update public.products
  set
    active = false,
    archived_at = statement_timestamp() + interval '1 second'
  where id = test.later_independent_product_id;

  update public.products
  set category_id = test.other_category_id
  where id = test.reassigned_product_id;

  if (
    select count(*)
    from public.products p
    where p.id in (
      test.later_independent_product_id,
      test.reassigned_product_id
    )
      and not p.active
      and p.archived_at is not null
      and p.archived_by_category_id is null
      and p.active_before_category_archive is null
      and p.category_archive_operation_id is null
  ) <> 2 then
    raise exception
      'Later independent archive/reassignment retained category provenance';
  end if;

  restore_result := public.admin_restore_category(test.category_id);
  if coalesce(
    (restore_result->>'restored_product_count')::integer,
    -1
  ) <> 2 or (restore_result->>'changed')::boolean is not true then
    raise exception
      'Expected two category products to be restored, got %',
      restore_result;
  end if;

  if not exists (
    select 1
    from public.categories c
    where c.id = test.category_id
      and c.active
      and c.archived_at is null
      and c.active_before_category_archive is null
      and c.category_archive_operation_id is null
  ) then
    raise exception 'Category restore state was not persisted';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = test.active_product_id
      and p.active
      and p.archived_at is null
      and p.archived_by_category_id is null
      and p.active_before_category_archive is null
      and p.category_archive_operation_id is null
  ) then
    raise exception 'Previously active category product was not restored active';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = test.inactive_product_id
      and not p.active
      and p.archived_at is null
      and p.archived_by_category_id is null
      and p.active_before_category_archive is null
      and p.category_archive_operation_id is null
  ) then
    raise exception
      'Previously hidden category product did not remain hidden after restore';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = test.independently_archived_product_id
      and not p.active
      and p.archived_at is not null
      and p.archived_by_category_id is null
      and p.active_before_category_archive is null
      and p.category_archive_operation_id is null
  ) then
    raise exception
      'Category restore revived an independently archived product';
  end if;

  if (
    select count(*)
    from public.products p
    where p.id in (
      test.later_independent_product_id,
      test.reassigned_product_id
    )
      and not p.active
      and p.archived_at is not null
      and p.archived_by_category_id is null
      and p.active_before_category_archive is null
      and p.category_archive_operation_id is null
  ) <> 2 then
    raise exception
      'Category restore revived a later independently changed product';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = test.reassigned_product_id
      and p.category_id = test.other_category_id
  ) then
    raise exception 'Category restore reverted a later product reassignment';
  end if;

  select count(*)
  into v_restore_audit_count
  from public.audit_logs log
  where log.entity_table = 'categories'
    and log.entity_id = test.category_id
    and log.action = 'category.restored';

  if v_restore_audit_count <> 1 then
    raise exception 'Category restore audit event was not written exactly once';
  end if;

  repeated_restore_result :=
    public.admin_restore_category(test.category_id);
  if coalesce(
    (repeated_restore_result->>'restored_product_count')::integer,
    -1
  ) <> 0
    or (repeated_restore_result->>'changed')::boolean is not false
  then
    raise exception 'Repeated category restore was not idempotent';
  end if;

  select count(*)
  into v_restore_audit_count
  from public.audit_logs log
  where log.entity_table = 'categories'
    and log.entity_id = test.category_id
    and log.action = 'category.restored';

  if v_restore_audit_count <> 1 then
    raise exception 'Repeated category restore duplicated its audit event';
  end if;

  inactive_archive_result :=
    public.admin_archive_category(test.inactive_category_id);
  if (inactive_archive_result->>'changed')::boolean is not true
    or not exists (
      select 1
      from public.categories c
      where c.id = test.inactive_category_id
        and not c.active
        and c.archived_at is not null
        and c.active_before_category_archive is false
        and c.category_archive_operation_id is not null
    )
  then
    raise exception
      'Inactive category visibility was not preserved during archive';
  end if;

  inactive_restore_result :=
    public.admin_restore_category(test.inactive_category_id);
  if (inactive_restore_result->>'changed')::boolean is not true
    or not exists (
      select 1
      from public.categories c
      where c.id = test.inactive_category_id
        and not c.active
        and c.archived_at is null
        and c.active_before_category_archive is null
        and c.category_archive_operation_id is null
    )
  then
    raise exception
      'Previously inactive category was incorrectly published on restore';
  end if;

  begin
    delete from public.categories
    where id = test.inactive_category_id;
    raise exception 'Authenticated actor permanently deleted a category';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

reset role;

rollback;
