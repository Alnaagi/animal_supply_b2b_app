\set ON_ERROR_STOP on

-- Rollback-only verification for migration 202608140035.
--
-- Required psql variables:
--   admin_profile_id  active admin profile UUID
--
-- Run against a local or staging database after applying migrations:
--
--   psql "$DATABASE_URL" \
--     -f supabase/tests/catalog_product_sorting.sql \
--     -v admin_profile_id=...

begin;

select set_config(
  'test.admin_profile_id',
  :'admin_profile_id',
  true
);

do $$
declare
  v_function regprocedure := to_regprocedure(
    'public.catalog_products_page(text,text,text,text,text,numeric,numeric,text,boolean,timestamptz,integer,integer,text)'
  );
begin
  if v_function is null then
    raise exception 'The 13-argument catalog sorting RPC is missing';
  end if;

  if to_regprocedure(
    'public.catalog_products_page(text,text,text,text,text,numeric,numeric,text,boolean,timestamptz,integer,integer)'
  ) is not null then
    raise exception 'The legacy 12-argument catalog RPC overload remains';
  end if;

  if not exists (
    select 1
    from pg_proc function_definition
    where function_definition.oid = v_function
      and function_definition.pronargs = 13
      and function_definition.pronargdefaults = 13
      and function_definition.provolatile = 's'
      and not function_definition.prosecdef
  ) then
    raise exception
      'Catalog sorting RPC signature, defaults, stability, or invoker security changed';
  end if;

  if not has_function_privilege(
    'authenticated',
    v_function,
    'EXECUTE'
  ) then
    raise exception 'Authenticated actors cannot execute catalog sorting RPC';
  end if;

  if has_function_privilege(
    'anon',
    v_function,
    'EXECUTE'
  ) or has_function_privilege(
    'service_role',
    v_function,
    'EXECUTE'
  ) then
    raise exception 'Catalog sorting RPC execute access is broader than intended';
  end if;

  if not exists (
    select 1
    from public.profiles profile
    where profile.id = current_setting('test.admin_profile_id')::uuid
      and profile.role = 'admin'
      and profile.active
  ) then
    raise exception 'admin_profile_id must reference an active admin profile';
  end if;
end;
$$;

create temporary table catalog_sorting_context (
  category_id uuid not null,
  category_name text not null,
  brand text not null,
  animal_type text not null,
  unit_size text not null,
  first_product_id uuid not null,
  second_product_id uuid not null,
  third_product_id uuid not null,
  untracked_product_id uuid not null
) on commit drop;

do $$
declare
  v_category_id uuid;
  v_first_product_id uuid;
  v_second_product_id uuid;
  v_third_product_id uuid;
  v_untracked_product_id uuid;
  v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  v_category_name text := 'اختبار ترتيب المنتجات ' || v_suffix;
  v_brand text := 'SORT-BRAND-' || v_suffix;
  v_animal_type text := 'SORT-ANIMAL-' || v_suffix;
  v_unit_size text := 'SORT-UNIT-' || v_suffix;
begin
  insert into public.categories (name, active)
  values (v_category_name, true)
  returning id into v_category_id;

  insert into public.products (
    category_id,
    name,
    sku,
    brand,
    animal_type,
    unit_size,
    base_price,
    stock_quantity,
    min_order_quantity,
    stock_tracking_enabled,
    active,
    created_at,
    updated_at
  )
  values (
    v_category_id,
    '01 منتج ترتيب ألف',
    'SORT-A-' || v_suffix,
    v_brand,
    v_animal_type,
    v_unit_size,
    40,
    30,
    1,
    true,
    true,
    '2024-01-01 00:00:00+00',
    '2024-01-01 00:00:00+00'
  )
  returning id into v_first_product_id;

  insert into public.products (
    category_id,
    name,
    sku,
    brand,
    animal_type,
    unit_size,
    base_price,
    stock_quantity,
    min_order_quantity,
    stock_tracking_enabled,
    active,
    created_at,
    updated_at
  )
  values (
    v_category_id,
    '02 منتج ترتيب باء',
    'SORT-B-' || v_suffix,
    v_brand,
    v_animal_type,
    v_unit_size,
    10,
    5,
    1,
    true,
    true,
    '2024-01-02 00:00:00+00',
    '2024-01-02 00:00:00+00'
  )
  returning id into v_second_product_id;

  insert into public.products (
    category_id,
    name,
    sku,
    brand,
    animal_type,
    unit_size,
    base_price,
    stock_quantity,
    min_order_quantity,
    stock_tracking_enabled,
    active,
    created_at,
    updated_at
  )
  values (
    v_category_id,
    '03 منتج ترتيب جيم',
    'SORT-C-' || v_suffix,
    v_brand,
    v_animal_type,
    v_unit_size,
    30,
    15,
    1,
    true,
    true,
    '2024-01-03 00:00:00+00',
    '2024-01-03 00:00:00+00'
  )
  returning id into v_third_product_id;

  insert into public.products (
    category_id,
    name,
    sku,
    brand,
    animal_type,
    unit_size,
    base_price,
    stock_quantity,
    min_order_quantity,
    stock_tracking_enabled,
    active,
    created_at,
    updated_at
  )
  values (
    v_category_id,
    '04 منتج ترتيب دال',
    'SORT-D-' || v_suffix,
    v_brand,
    v_animal_type,
    v_unit_size,
    20,
    999,
    1,
    false,
    true,
    '2024-01-04 00:00:00+00',
    '2024-01-04 00:00:00+00'
  )
  returning id into v_untracked_product_id;

  insert into catalog_sorting_context (
    category_id,
    category_name,
    brand,
    animal_type,
    unit_size,
    first_product_id,
    second_product_id,
    third_product_id,
    untracked_product_id
  )
  values (
    v_category_id,
    v_category_name,
    v_brand,
    v_animal_type,
    v_unit_size,
    v_first_product_id,
    v_second_product_id,
    v_third_product_id,
    v_untracked_product_id
  );
end;
$$;

grant select on catalog_sorting_context to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'admin_profile_id',
  true
);

do $$
declare
  test catalog_sorting_context%rowtype;
  result jsonb;
  actual_ids uuid[];
  expected_ids uuid[];
begin
  select * into test from catalog_sorting_context;

  result := public.catalog_products_page(
    p_category => test.category_name,
    p_brand => test.brand,
    p_include_inactive => true,
    p_limit => 100,
    p_sort => 'newest'
  );
  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(result->'products')
    with ordinality as item(value, ordinality);
  expected_ids := array[
    test.untracked_product_id,
    test.third_product_id,
    test.second_product_id,
    test.first_product_id
  ];
  if actual_ids is distinct from expected_ids then
    raise exception
      'Newest product order mismatch. Expected %, got %',
      expected_ids,
      actual_ids;
  end if;
  if (result->>'has_more')::boolean
    or (result->>'next_offset')::integer <> 4
    or result->>'snapshot_at' is null
  then
    raise exception 'Newest page metadata changed: %', result;
  end if;
  if exists (
    select 1
    from jsonb_array_elements(result->'products') item(value)
    where item.value ? 'sort_position'
  ) then
    raise exception 'Internal sort position leaked into catalog JSON';
  end if;

  result := public.catalog_products_page(
    p_category => test.category_name,
    p_brand => test.brand,
    p_include_inactive => true,
    p_limit => 100
  );
  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(result->'products')
    with ordinality as item(value, ordinality);
  if actual_ids is distinct from expected_ids then
    raise exception
      'Omitted sort did not preserve newest default. Expected %, got %',
      expected_ids,
      actual_ids;
  end if;

  result := public.catalog_products_page(
    p_category => test.category_name,
    p_brand => test.brand,
    p_include_inactive => true,
    p_limit => 100,
    p_sort => 'unsupported-sort'
  );
  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(result->'products')
    with ordinality as item(value, ordinality);
  if actual_ids is distinct from expected_ids then
    raise exception
      'Invalid sort did not fall back to newest. Expected %, got %',
      expected_ids,
      actual_ids;
  end if;

  result := public.catalog_products_page(
    p_category => test.category_name,
    p_brand => test.brand,
    p_include_inactive => true,
    p_limit => 100,
    p_sort => 'oldest'
  );
  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(result->'products')
    with ordinality as item(value, ordinality);
  expected_ids := array[
    test.first_product_id,
    test.second_product_id,
    test.third_product_id,
    test.untracked_product_id
  ];
  if actual_ids is distinct from expected_ids then
    raise exception
      'Oldest product order mismatch. Expected %, got %',
      expected_ids,
      actual_ids;
  end if;

  result := public.catalog_products_page(
    p_category => test.category_name,
    p_brand => test.brand,
    p_include_inactive => true,
    p_limit => 100,
    p_sort => 'name_asc'
  );
  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(result->'products')
    with ordinality as item(value, ordinality);
  if actual_ids is distinct from expected_ids then
    raise exception
      'Name product order mismatch. Expected %, got %',
      expected_ids,
      actual_ids;
  end if;

  result := public.catalog_products_page(
    p_category => test.category_name,
    p_brand => test.brand,
    p_include_inactive => true,
    p_limit => 100,
    p_sort => 'price_asc'
  );
  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(result->'products')
    with ordinality as item(value, ordinality);
  expected_ids := array[
    test.second_product_id,
    test.untracked_product_id,
    test.third_product_id,
    test.first_product_id
  ];
  if actual_ids is distinct from expected_ids then
    raise exception
      'Ascending price order mismatch. Expected %, got %',
      expected_ids,
      actual_ids;
  end if;

  result := public.catalog_products_page(
    p_category => test.category_name,
    p_brand => test.brand,
    p_include_inactive => true,
    p_limit => 100,
    p_sort => 'price_desc'
  );
  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(result->'products')
    with ordinality as item(value, ordinality);
  expected_ids := array[
    test.first_product_id,
    test.third_product_id,
    test.untracked_product_id,
    test.second_product_id
  ];
  if actual_ids is distinct from expected_ids then
    raise exception
      'Descending price order mismatch. Expected %, got %',
      expected_ids,
      actual_ids;
  end if;

  result := public.catalog_products_page(
    p_category => test.category_name,
    p_brand => test.brand,
    p_include_inactive => true,
    p_limit => 100,
    p_sort => 'stock_asc'
  );
  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(result->'products')
    with ordinality as item(value, ordinality);
  expected_ids := array[
    test.second_product_id,
    test.third_product_id,
    test.first_product_id,
    test.untracked_product_id
  ];
  if actual_ids is distinct from expected_ids then
    raise exception
      'Ascending stock order mismatch. Expected %, got %',
      expected_ids,
      actual_ids;
  end if;

  result := public.catalog_products_page(
    p_category => test.category_name,
    p_brand => test.brand,
    p_include_inactive => true,
    p_limit => 100,
    p_sort => 'stock_desc'
  );
  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(result->'products')
    with ordinality as item(value, ordinality);
  expected_ids := array[
    test.first_product_id,
    test.third_product_id,
    test.second_product_id,
    test.untracked_product_id
  ];
  if actual_ids is distinct from expected_ids then
    raise exception
      'Descending stock order mismatch. Expected %, got %',
      expected_ids,
      actual_ids;
  end if;

  result := public.catalog_products_page(
    p_query => 'منتج ترتيب',
    p_category => test.category_name,
    p_brand => test.brand,
    p_animal_type => test.animal_type,
    p_unit_size => test.unit_size,
    p_min_price => 20,
    p_max_price => 35,
    p_availability => 'in_stock',
    p_include_inactive => true,
    p_limit => 100,
    p_sort => 'price_desc'
  );
  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(result->'products')
    with ordinality as item(value, ordinality);
  expected_ids := array[
    test.third_product_id,
    test.untracked_product_id
  ];
  if actual_ids is distinct from expected_ids then
    raise exception
      'Catalog filters did not compose with sorting. Expected %, got %',
      expected_ids,
      actual_ids;
  end if;
end;
$$;

rollback;
