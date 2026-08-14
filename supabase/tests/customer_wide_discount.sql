\set ON_ERROR_STOP on

-- Rollback-only verification for migration 202608140036.
--
-- Required psql variables:
--   customer_profile_id  active, unlocked customer profile UUID
--   admin_profile_id     active, unlocked admin profile UUID
--
-- Run against an isolated local or staging database after applying migrations:
--
--   psql "$DATABASE_URL" \
--     -f supabase/tests/customer_wide_discount.sql \
--     -v customer_profile_id=... \
--     -v admin_profile_id=...

begin;

select set_config(
  'test.customer_profile_id',
  :'customer_profile_id',
  true
);
select set_config(
  'test.admin_profile_id',
  :'admin_profile_id',
  true
);

do $$
declare
  v_discount_column record;
  v_discount_constraint record;
  v_helper regprocedure := to_regprocedure(
    'public.apply_customer_discount(numeric,numeric)'
  );
  v_effective_price regprocedure := to_regprocedure(
    'public.effective_product_price(uuid,uuid)'
  );
  v_catalog_detail regprocedure := to_regprocedure(
    'public.catalog_products(uuid)'
  );
  v_catalog_page regprocedure := to_regprocedure(
    'public.catalog_products_page(text,text,text,text,text,numeric,numeric,text,boolean,timestamptz,integer,integer,text)'
  );
  v_bootstrap regprocedure := to_regprocedure(
    'public.bootstrap_current_account()'
  );
  v_update_v2 regprocedure := to_regprocedure(
    'public.admin_update_business_customer_v2(uuid,uuid,text,text,text,text,text,text,numeric,text,numeric,numeric)'
  );
  v_update_legacy regprocedure := to_regprocedure(
    'public.admin_update_business_customer(uuid,uuid,text,text,text,text,text,text,uuid,text,numeric,numeric)'
  );
begin
  select
    column_row.data_type,
    column_row.numeric_precision,
    column_row.numeric_scale,
    column_row.is_nullable,
    column_row.column_default
  into v_discount_column
  from information_schema.columns column_row
  where column_row.table_schema = 'public'
    and column_row.table_name = 'business_customers'
    and column_row.column_name = 'discount_percent';

  if not found
    or v_discount_column.data_type <> 'numeric'
    or v_discount_column.numeric_precision <> 5
    or v_discount_column.numeric_scale <> 2
    or v_discount_column.is_nullable <> 'NO'
    or v_discount_column.column_default is null
  then
    raise exception
      'business_customers.discount_percent contract is incomplete: %',
      row_to_json(v_discount_column);
  end if;

  select
    constraint_row.oid is not null as exists,
    constraint_row.convalidated as validated
  into v_discount_constraint
  from pg_constraint constraint_row
  where constraint_row.conname = 'business_customers_discount_percent_range'
    and constraint_row.conrelid = 'public.business_customers'::regclass;

  if not found
    or not v_discount_constraint.exists
    or not v_discount_constraint.validated
  then
    raise exception 'Customer discount range constraint is missing or invalid';
  end if;

  if v_helper is null
    or v_effective_price is null
    or v_catalog_detail is null
    or v_catalog_page is null
    or v_bootstrap is null
    or v_update_v2 is null
    or v_update_legacy is null
  then
    raise exception 'One or more customer-wide discount functions are missing';
  end if;

  if not exists (
    select 1
    from pg_proc function_row
    where function_row.oid = v_helper
      and function_row.provolatile = 'i'
      and function_row.proparallel = 's'
      and not function_row.prosecdef
  ) then
    raise exception
      'apply_customer_discount must remain immutable, parallel-safe, and invoker-security';
  end if;

  if has_function_privilege('anon', v_helper, 'EXECUTE')
    or not has_function_privilege('authenticated', v_helper, 'EXECUTE')
    or not has_function_privilege('service_role', v_helper, 'EXECUTE')
  then
    raise exception 'Discount helper grants are broader or narrower than intended';
  end if;

  if has_function_privilege('anon', v_effective_price, 'EXECUTE')
    or has_function_privilege('authenticated', v_effective_price, 'EXECUTE')
    or has_function_privilege('service_role', v_effective_price, 'EXECUTE')
  then
    raise exception 'Authoritative effective-price helper is directly executable';
  end if;

  if has_function_privilege('anon', v_update_v2, 'EXECUTE')
    or has_function_privilege('authenticated', v_update_v2, 'EXECUTE')
    or not has_function_privilege('service_role', v_update_v2, 'EXECUTE')
  then
    raise exception 'Customer update v2 grants are incorrect';
  end if;

  if has_function_privilege('anon', v_update_legacy, 'EXECUTE')
    or has_function_privilege('authenticated', v_update_legacy, 'EXECUTE')
    or not has_function_privilege('service_role', v_update_legacy, 'EXECUTE')
  then
    raise exception 'Legacy customer update wrapper grants are incorrect';
  end if;

  if has_function_privilege('anon', v_catalog_detail, 'EXECUTE')
    or not has_function_privilege('authenticated', v_catalog_detail, 'EXECUTE')
    or has_function_privilege('service_role', v_catalog_detail, 'EXECUTE')
  then
    raise exception 'Catalog detail grants are incorrect';
  end if;

  if has_function_privilege('anon', v_catalog_page, 'EXECUTE')
    or not has_function_privilege('authenticated', v_catalog_page, 'EXECUTE')
    or has_function_privilege('service_role', v_catalog_page, 'EXECUTE')
  then
    raise exception 'Catalog page grants are incorrect';
  end if;

  if has_function_privilege('anon', v_bootstrap, 'EXECUTE')
    or not has_function_privilege('authenticated', v_bootstrap, 'EXECUTE')
    or has_function_privilege('service_role', v_bootstrap, 'EXECUTE')
  then
    raise exception 'Account bootstrap grants are incorrect';
  end if;
end;
$$;

do $$
begin
  if public.apply_customer_discount(100, 10) <> 90.00 then
    raise exception 'Basic customer discount calculation is incorrect';
  end if;

  if public.apply_customer_discount(99.99, 12.50) <> 87.49 then
    raise exception 'Customer discount rounding is incorrect';
  end if;

  if public.apply_customer_discount(0.01, 99.99) <> 0.01 then
    raise exception 'Positive customer price floor is incorrect';
  end if;

  if public.apply_customer_discount(0, 50) <> 0 then
    raise exception 'Zero base price behavior changed';
  end if;
end;
$$;

create temporary table customer_discount_context (
  customer_profile_id uuid not null,
  admin_profile_id uuid not null,
  customer_id uuid not null,
  original_price_group_id uuid,
  legacy_price_group_id uuid not null,
  ignored_price_group_id uuid not null,
  category_id uuid not null,
  high_product_id uuid not null,
  low_product_id uuid not null,
  first_request_id uuid not null,
  second_request_id uuid not null,
  first_order_id uuid,
  second_order_id uuid
) on commit drop;

do $$
declare
  v_customer_id uuid;
  v_original_price_group_id uuid;
  v_legacy_price_group_id uuid;
  v_ignored_price_group_id uuid;
  v_category_id uuid;
  v_high_product_id uuid;
  v_low_product_id uuid;
  v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
begin
  if not exists (
    select 1
    from public.profiles profile
    where profile.id = current_setting('test.admin_profile_id')::uuid
      and profile.role = 'admin'
      and profile.active
      and not profile.must_change_password
  ) then
    raise exception 'admin_profile_id must reference an active unlocked admin';
  end if;

  select customer.id, customer.price_group_id
  into v_customer_id, v_original_price_group_id
  from public.business_customers customer
  join public.profiles profile
    on profile.id = customer.profile_id
  where profile.id = current_setting('test.customer_profile_id')::uuid
    and profile.role = 'customer'
    and profile.active
    and not profile.must_change_password
    and customer.account_status = 'active'
    and customer.archived_at is null;

  if not found then
    raise exception
      'customer_profile_id must reference an active unlocked customer';
  end if;

  insert into public.price_groups (name, description, active)
  values (
    'LEGACY-DISCOUNT-' || v_suffix,
    'Legacy pricing row used only by rollback verification',
    true
  )
  returning id into v_legacy_price_group_id;

  insert into public.price_groups (name, description, active)
  values (
    'IGNORED-DISCOUNT-' || v_suffix,
    'Ignored compatibility argument used by rollback verification',
    true
  )
  returning id into v_ignored_price_group_id;

  insert into public.categories (name, active)
  values ('اختبار خصم العميل ' || v_suffix, true)
  returning id into v_category_id;

  insert into public.products (
    category_id,
    name,
    sku,
    brand,
    animal_type,
    unit_size,
    package_size,
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
    '02 منتج خصم مرتفع',
    'CUST-DISCOUNT-HIGH-' || v_suffix,
    'DISCOUNT-BRAND-' || v_suffix,
    'DISCOUNT-ANIMAL-' || v_suffix,
    'DISCOUNT-UNIT-' || v_suffix,
    'DISCOUNT-PACK-' || v_suffix,
    100,
    0,
    1,
    false,
    true,
    '2026-08-14 10:00:00+00',
    '2026-08-14 10:00:00+00'
  )
  returning id into v_high_product_id;

  insert into public.products (
    category_id,
    name,
    sku,
    brand,
    animal_type,
    unit_size,
    package_size,
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
    '01 منتج خصم منخفض',
    'CUST-DISCOUNT-LOW-' || v_suffix,
    'DISCOUNT-BRAND-' || v_suffix,
    'DISCOUNT-ANIMAL-' || v_suffix,
    'DISCOUNT-UNIT-' || v_suffix,
    'DISCOUNT-PACK-' || v_suffix,
    80,
    0,
    1,
    false,
    true,
    '2026-08-14 09:00:00+00',
    '2026-08-14 09:00:00+00'
  )
  returning id into v_low_product_id;

  update public.business_customers
  set
    price_group_id = v_legacy_price_group_id,
    discount_percent = 10
  where id = v_customer_id;

  insert into public.product_prices (
    product_id,
    price_group_id,
    price
  )
  values
    (v_high_product_id, v_legacy_price_group_id, 1),
    (v_low_product_id, v_legacy_price_group_id, 1);

  insert into public.customer_special_prices (
    customer_id,
    product_id,
    price,
    active
  )
  values
    (v_customer_id, v_high_product_id, 2, true),
    (v_customer_id, v_low_product_id, 3, true);

  insert into customer_discount_context (
    customer_profile_id,
    admin_profile_id,
    customer_id,
    original_price_group_id,
    legacy_price_group_id,
    ignored_price_group_id,
    category_id,
    high_product_id,
    low_product_id,
    first_request_id,
    second_request_id
  )
  values (
    current_setting('test.customer_profile_id')::uuid,
    current_setting('test.admin_profile_id')::uuid,
    v_customer_id,
    v_original_price_group_id,
    v_legacy_price_group_id,
    v_ignored_price_group_id,
    v_category_id,
    v_high_product_id,
    v_low_product_id,
    gen_random_uuid(),
    gen_random_uuid()
  );

  insert into public.app_settings (key, value)
  values
    ('minimum_order_amount', '0'),
    ('delivery_fee', '0'),
    ('handling_fee', '0')
  on conflict (key) do update
  set value = excluded.value;
end;
$$;

grant select on customer_discount_context to authenticated;

do $$
declare
  test customer_discount_context%rowtype;
begin
  select * into test from customer_discount_context;

  begin
    update public.business_customers
    set discount_percent = -0.01
    where id = test.customer_id;
    raise exception 'Negative customer discount was accepted';
  exception
    when check_violation then null;
  end;

  begin
    update public.business_customers
    set discount_percent = 100
    where id = test.customer_id;
    raise exception 'A 100 percent customer discount was accepted';
  exception
    when check_violation then null;
  end;

  if (
    select customer.discount_percent
    from public.business_customers customer
    where customer.id = test.customer_id
  ) <> 10 then
    raise exception 'Constraint failures changed the valid customer discount';
  end if;
end;
$$;

do $$
declare
  v_signature text;
  v_definition text;
begin
  foreach v_signature in array array[
    'public.effective_product_price(uuid,uuid)',
    'public.catalog_products(uuid)',
    'public.catalog_products_page(text,text,text,text,text,numeric,numeric,text,boolean,timestamptz,integer,integer,text)',
    'public.bootstrap_current_account()',
    'public.admin_update_business_customer_v2(uuid,uuid,text,text,text,text,text,text,numeric,text,numeric,numeric)',
    'public.admin_update_business_customer(uuid,uuid,text,text,text,text,text,text,uuid,text,numeric,numeric)',
    'public.place_order_transaction_impl(uuid,uuid,jsonb,text,text,text)'
  ]
  loop
    select lower(pg_get_functiondef(to_regprocedure(v_signature)))
    into v_definition;

    if v_definition like '%product_prices%'
      or v_definition like '%customer_special_prices%'
      or v_definition like '%public.price_groups%'
    then
      raise exception
        'Runtime function % still consults a legacy pricing table',
        v_signature;
    end if;
  end loop;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'customer_profile_id',
  true
);

do $$
declare
  test customer_discount_context%rowtype;
  detail record;
  page_result jsonb;
  actual_ids uuid[];
  filtered_ids uuid[];
  bootstrap jsonb;
begin
  select * into test from customer_discount_context;

  select *
  into detail
  from public.catalog_products(test.high_product_id);

  if not found
    or detail.base_price <> 100
    or detail.effective_price <> 90
  then
    raise exception
      'Customer detail price did not use the customer-wide discount: %',
      row_to_json(detail);
  end if;

  page_result := public.catalog_products_page(
    p_category => (
      select category.name
      from public.categories category
      where category.id = test.category_id
    ),
    p_brand => (
      select product.brand
      from public.products product
      where product.id = test.high_product_id
    ),
    p_limit => 100,
    p_sort => 'price_asc'
  );

  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(page_result->'products')
    with ordinality as item(value, ordinality);

  if actual_ids is distinct from array[
    test.low_product_id,
    test.high_product_id
  ] then
    raise exception
      'Customer discounted price sorting mismatch: %',
      actual_ids;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(page_result->'products') item(value)
    where (
      item.value->>'id' = test.low_product_id::text
      and (item.value->>'effective_price')::numeric <> 72
    ) or (
      item.value->>'id' = test.high_product_id::text
      and (item.value->>'effective_price')::numeric <> 90
    )
  ) then
    raise exception 'Customer catalog page returned incorrect discounted prices';
  end if;

  page_result := public.catalog_products_page(
    p_category => (
      select category.name
      from public.categories category
      where category.id = test.category_id
    ),
    p_min_price => 89,
    p_max_price => 91,
    p_limit => 100,
    p_sort => 'price_asc'
  );

  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into filtered_ids
  from jsonb_array_elements(page_result->'products')
    with ordinality as item(value, ordinality);

  if filtered_ids is distinct from array[test.high_product_id] then
    raise exception
      'Customer discounted price filter mismatch: %',
      filtered_ids;
  end if;

  bootstrap := public.bootstrap_current_account();
  if (bootstrap->'customer'->>'discount_percent')::numeric <> 10
    or (bootstrap->'customer') ? 'price_group'
  then
    raise exception
      'Customer bootstrap did not replace price group with discount: %',
      bootstrap;
  end if;

  begin
    update public.business_customers
    set discount_percent = 20
    where id = test.customer_id;
    raise exception 'Authenticated customer directly updated its discount';
  exception
    when insufficient_privilege then null;
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
  test customer_discount_context%rowtype;
  detail record;
  page_result jsonb;
  actual_ids uuid[];
begin
  select * into test from customer_discount_context;

  select *
  into detail
  from public.catalog_products(test.high_product_id);

  if not found
    or detail.base_price <> 100
    or detail.effective_price <> 100
  then
    raise exception
      'Admin detail price must remain the base price: %',
      row_to_json(detail);
  end if;

  page_result := public.catalog_products_page(
    p_category => (
      select category.name
      from public.categories category
      where category.id = test.category_id
    ),
    p_include_inactive => true,
    p_limit => 100,
    p_sort => 'price_asc'
  );

  select coalesce(
    array_agg((item.value->>'id')::uuid order by item.ordinality),
    '{}'::uuid[]
  )
  into actual_ids
  from jsonb_array_elements(page_result->'products')
    with ordinality as item(value, ordinality);

  if actual_ids is distinct from array[
    test.low_product_id,
    test.high_product_id
  ] then
    raise exception 'Admin base-price sorting mismatch: %', actual_ids;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(page_result->'products') item(value)
    where (
      item.value->>'id' = test.low_product_id::text
      and (item.value->>'effective_price')::numeric <> 80
    ) or (
      item.value->>'id' = test.high_product_id::text
      and (item.value->>'effective_price')::numeric <> 100
    )
  ) then
    raise exception 'Admin catalog page returned discounted prices';
  end if;
end;
$$;

reset role;

do $$
declare
  test customer_discount_context%rowtype;
  customer public.business_customers%rowtype;
  response jsonb;
  audit public.audit_logs%rowtype;
begin
  select * into test from customer_discount_context;
  select * into customer
  from public.business_customers
  where id = test.customer_id;

  response := public.admin_update_business_customer_v2(
    test.admin_profile_id,
    customer.id,
    customer.business_name,
    customer.contact_person,
    customer.phone,
    customer.city,
    customer.area,
    customer.address,
    15.25,
    customer.account_status,
    customer.credit_limit,
    customer.outstanding_balance
  );

  if (response->>'discount_percent')::numeric <> 15.25 then
    raise exception 'Customer update v2 returned an incorrect discount: %', response;
  end if;

  select * into customer
  from public.business_customers
  where id = test.customer_id;

  if customer.discount_percent <> 15.25
    or customer.price_group_id is distinct from test.legacy_price_group_id
  then
    raise exception
      'Customer update v2 changed the wrong pricing state: %',
      row_to_json(customer);
  end if;

  select *
  into audit
  from public.audit_logs log
  where log.actor_id = test.admin_profile_id
    and log.action = 'customer.updated'
    and log.entity_table = 'business_customers'
    and log.entity_id = test.customer_id
  order by log.created_at desc, log.id desc
  limit 1;

  if not found
    or not (audit.metadata->'changed_fields' ? 'discount_percent')
    or (audit.metadata->'discount_percent'->>'from')::numeric <> 10
    or (audit.metadata->'discount_percent'->>'to')::numeric <> 15.25
  then
    raise exception
      'Customer discount audit metadata is incomplete: %',
      row_to_json(audit);
  end if;

  response := public.admin_update_business_customer_v2(
    test.admin_profile_id,
    customer.id,
    customer.business_name,
    customer.contact_person,
    customer.phone,
    customer.city,
    customer.area,
    customer.address,
    null,
    customer.account_status,
    customer.credit_limit,
    customer.outstanding_balance
  );

  select * into customer
  from public.business_customers
  where id = test.customer_id;

  if customer.discount_percent <> 15.25
    or (response->>'discount_percent')::numeric <> 15.25
  then
    raise exception
      'Nullable v2 discount did not preserve the locked customer value';
  end if;

  begin
    perform public.admin_update_business_customer_v2(
      test.customer_profile_id,
      customer.id,
      customer.business_name,
      customer.contact_person,
      customer.phone,
      customer.city,
      customer.area,
      customer.address,
      20,
      customer.account_status,
      customer.credit_limit,
      customer.outstanding_balance
    );
    raise exception 'Customer actor executed the privileged update RPC';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'STAFF_AUTH_REQUIRED' then
        raise;
      end if;
  end;

  begin
    perform public.admin_update_business_customer_v2(
      test.admin_profile_id,
      customer.id,
      customer.business_name,
      customer.contact_person,
      customer.phone,
      customer.city,
      customer.area,
      customer.address,
      100,
      customer.account_status,
      customer.credit_limit,
      customer.outstanding_balance
    );
    raise exception 'Customer update v2 accepted a 100 percent discount';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'CUSTOMER_UPDATE_INVALID' then
        raise;
      end if;
  end;

  response := public.admin_update_business_customer(
    test.admin_profile_id,
    customer.id,
    customer.business_name,
    customer.contact_person,
    customer.phone,
    customer.city,
    customer.area,
    customer.address,
    test.ignored_price_group_id,
    customer.account_status,
    customer.credit_limit,
    customer.outstanding_balance
  );

  select * into customer
  from public.business_customers
  where id = test.customer_id;

  if customer.discount_percent <> 15.25
    or customer.price_group_id is distinct from test.legacy_price_group_id
    or (response->>'discount_percent')::numeric <> 15.25
  then
    raise exception
      'Legacy customer update wrapper did not preserve discount/group state';
  end if;
end;
$$;

update public.profiles
set must_change_password = true
where id = :'customer_profile_id'::uuid;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'customer_profile_id',
  true
);

do $$
declare
  bootstrap jsonb;
begin
  bootstrap := public.bootstrap_current_account();
  if (bootstrap->'customer') ? 'discount_percent'
    or (bootstrap->'customer') ? 'price_group'
  then
    raise exception
      'Pre-activation bootstrap exposed customer pricing details: %',
      bootstrap;
  end if;
end;
$$;

reset role;

update public.profiles
set must_change_password = false
where id = :'customer_profile_id'::uuid;

do $$
declare
  test customer_discount_context%rowtype;
  customer public.business_customers%rowtype;
  first_response jsonb;
  retry_response jsonb;
  second_response jsonb;
  first_order_id uuid;
  retry_order_id uuid;
  second_order_id uuid;
  first_item public.order_items%rowtype;
  second_item public.order_items%rowtype;
  first_order public.orders%rowtype;
  second_order public.orders%rowtype;
begin
  select * into test from customer_discount_context;
  select * into customer
  from public.business_customers
  where id = test.customer_id;

  first_response := public.place_order_transaction(
    test.customer_profile_id,
    test.first_request_id,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', test.low_product_id,
        'quantity', 2
      )
    ),
    'عنوان اختبار خصم العميل',
    'اختبار تسعير الخصم',
    null
  );
  first_order_id := (first_response->'order'->>'id')::uuid;

  select * into first_item
  from public.order_items item
  where item.order_id = first_order_id;
  select * into first_order
  from public.orders customer_order
  where customer_order.id = first_order_id;

  if first_item.unit_price <> 67.80
    or first_item.line_total <> 135.60
    or first_order.subtotal <> 135.60
  then
    raise exception
      'Authoritative order did not snapshot the customer discount: item %, order %',
      row_to_json(first_item),
      row_to_json(first_order);
  end if;

  perform public.admin_update_business_customer_v2(
    test.admin_profile_id,
    customer.id,
    customer.business_name,
    customer.contact_person,
    customer.phone,
    customer.city,
    customer.area,
    customer.address,
    25,
    customer.account_status,
    customer.credit_limit,
    customer.outstanding_balance
  );

  retry_response := public.place_order_transaction(
    test.customer_profile_id,
    test.first_request_id,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', test.low_product_id,
        'quantity', 2
      )
    ),
    'عنوان اختبار خصم العميل',
    'اختبار تسعير الخصم',
    null
  );
  retry_order_id := (retry_response->'order'->>'id')::uuid;

  if retry_order_id is distinct from first_order_id
    or coalesce((retry_response->>'idempotent')::boolean, false) is not true
    or (
      retry_response->'order'->'items'->0->>'unit_price'
    )::numeric <> 67.80
  then
    raise exception
      'Idempotent retry did not preserve the original discounted order: %',
      retry_response;
  end if;

  second_response := public.place_order_transaction(
    test.customer_profile_id,
    test.second_request_id,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', test.low_product_id,
        'quantity', 2
      )
    ),
    'عنوان اختبار خصم العميل الجديد',
    'اختبار الخصم الجديد',
    null
  );
  second_order_id := (second_response->'order'->>'id')::uuid;

  select * into second_item
  from public.order_items item
  where item.order_id = second_order_id;
  select * into second_order
  from public.orders customer_order
  where customer_order.id = second_order_id;

  if second_order_id = first_order_id
    or second_item.unit_price <> 60
    or second_item.line_total <> 120
    or second_order.subtotal <> 120
  then
    raise exception
      'New request did not use the newly assigned discount: item %, order %',
      row_to_json(second_item),
      row_to_json(second_order);
  end if;

end;
$$;

rollback;
