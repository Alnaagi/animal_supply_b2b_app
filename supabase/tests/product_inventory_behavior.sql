\set ON_ERROR_STOP on

-- Rollback-only verification for migration 202607220031.
--
-- Required psql variables:
--   customer_profile_id  active, unlocked customer profile UUID
--   admin_profile_id     active, unlocked admin profile UUID

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
begin
  if has_function_privilege(
    'authenticated',
    'public.place_order_transaction(uuid,uuid,jsonb,text,text,text)',
    'EXECUTE'
  ) then
    raise exception
      'Authenticated client can execute the service-only order transaction';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.place_order_transaction(uuid,uuid,jsonb,text,text,text)',
    'EXECUTE'
  ) then
    raise exception 'Service role cannot execute the order transaction';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.transition_order_status_transaction(uuid,uuid,text,text)',
    'EXECUTE'
  ) then
    raise exception
      'Authenticated client can execute the service-only status transition';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.transition_order_status_transaction(uuid,uuid,text,text)',
    'EXECUTE'
  ) then
    raise exception 'Service role cannot execute the status transition';
  end if;

  if has_function_privilege(
    'service_role',
    'public.place_order_transaction_impl(uuid,uuid,jsonb,text,text,text)',
    'EXECUTE'
  ) then
    raise exception
      'Service role can bypass the idempotent public order wrapper';
  end if;
end;
$$;

create temporary table product_behavior_context (
  hidden_product_id uuid,
  shown_unavailable_product_id uuid,
  untracked_product_id uuid,
  tracked_product_id uuid,
  untracked_order_id uuid,
  tracked_order_id uuid
) on commit drop;

insert into product_behavior_context default values;

do $$
declare
  v_category_id uuid;
  v_hidden_id uuid;
  v_shown_id uuid;
  v_untracked_id uuid;
  v_tracked_id uuid;
begin
  select c.id
  into v_category_id
  from public.categories c
  order by c.created_at
  limit 1;

  if v_category_id is null then
    insert into public.categories (name, icon_key)
    values ('اختبار سلوك المخزون', 'category')
    returning id into v_category_id;
  end if;

  insert into public.products (
    category_id,
    name,
    sku,
    brand,
    base_price,
    retail_unit_price,
    stock_quantity,
    min_order_quantity,
    units_per_box,
    stock_tracking_enabled,
    hide_when_out_of_stock,
    active
  )
  values (
    v_category_id,
    'منتج مخفي عند النفاد',
    'TEST-HIDDEN-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10),
    'شركة الاختبار',
    40,
    6,
    0,
    5,
    12,
    true,
    true,
    true
  )
  returning id into v_hidden_id;

  insert into public.products (
    category_id,
    name,
    sku,
    brand,
    base_price,
    retail_unit_price,
    stock_quantity,
    min_order_quantity,
    stock_tracking_enabled,
    hide_when_out_of_stock,
    active
  )
  values (
    v_category_id,
    'منتج ظاهر رغم النفاد',
    'TEST-SHOWN-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10),
    'شركة الاختبار',
    45,
    7,
    0,
    5,
    true,
    false,
    true
  )
  returning id into v_shown_id;

  insert into public.products (
    category_id,
    name,
    sku,
    brand,
    base_price,
    retail_unit_price,
    stock_quantity,
    min_order_quantity,
    units_per_box,
    stock_tracking_enabled,
    hide_when_out_of_stock,
    active
  )
  values (
    v_category_id,
    'منتج دون تتبع مخزون',
    'TEST-UNTRACKED-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8),
    'شركة الاختبار',
    50,
    8,
    0,
    5,
    24,
    false,
    true,
    true
  )
  returning id into v_untracked_id;

  insert into public.products (
    category_id,
    name,
    sku,
    brand,
    base_price,
    retail_unit_price,
    stock_quantity,
    min_order_quantity,
    stock_tracking_enabled,
    hide_when_out_of_stock,
    active
  )
  values (
    v_category_id,
    'منتج متتبع مع حجز',
    'TEST-TRACKED-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10),
    'شركة الاختبار',
    55,
    9,
    20,
    5,
    true,
    false,
    true
  )
  returning id into v_tracked_id;

  update product_behavior_context
  set
    hidden_product_id = v_hidden_id,
    shown_unavailable_product_id = v_shown_id,
    untracked_product_id = v_untracked_id,
    tracked_product_id = v_tracked_id;
end;
$$;

grant select on product_behavior_context to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  :'customer_profile_id',
  true
);

do $$
declare
  test product_behavior_context%rowtype;
  shown_record record;
  untracked_record record;
begin
  select * into test from product_behavior_context;

  if exists (
    select 1
    from public.catalog_products(test.hidden_product_id)
  ) then
    raise exception 'Hidden unavailable product remained customer-visible';
  end if;

  select *
  into shown_record
  from public.catalog_products(test.shown_unavailable_product_id);

  if not found or shown_record.is_orderable then
    raise exception
      'Shown unavailable product must remain visible and non-orderable';
  end if;

  select *
  into untracked_record
  from public.catalog_products(test.untracked_product_id);

  if not found
    or not untracked_record.is_orderable
    or untracked_record.available_quantity is not null
    or untracked_record.units_per_box <> 24
    or untracked_record.retail_unit_price <> 8
  then
    raise exception
      'Untracked product catalog metadata/orderability is incorrect';
  end if;
end;
$$;

reset role;

do $$
declare
  test product_behavior_context%rowtype;
  response jsonb;
begin
  select * into test from product_behavior_context;

  begin
    perform public.place_order_transaction(
      current_setting('test.customer_profile_id')::uuid,
      gen_random_uuid(),
      jsonb_build_array(
        jsonb_build_object(
          'product_id', test.untracked_product_id,
          'quantity', 5
        ),
        jsonb_build_object(
          'product_id', test.untracked_product_id,
          'quantity', -4
        )
      ),
      null,
      'اختبار رفض الكمية السالبة قبل التجميع',
      null
    );
    raise exception 'Negative raw order line was accepted after aggregation';
  exception
    when others then
      if sqlerrm <> 'INVALID_ORDER_ITEM' then
        raise;
      end if;
  end;

  response := public.place_order_transaction(
    current_setting('test.customer_profile_id')::uuid,
    gen_random_uuid(),
    jsonb_build_array(
      jsonb_build_object(
        'product_id', test.untracked_product_id,
        'quantity', 5
      )
    ),
    null,
    'اختبار منتج غير متتبع',
    null
  );

  update product_behavior_context
  set untracked_order_id = (response -> 'order' ->> 'id')::uuid;

  response := public.place_order_transaction(
    current_setting('test.customer_profile_id')::uuid,
    gen_random_uuid(),
    jsonb_build_array(
      jsonb_build_object(
        'product_id', test.tracked_product_id,
        'quantity', 5
      )
    ),
    null,
    'اختبار حماية تبديل التتبع',
    null
  );

  update product_behavior_context
  set tracked_order_id = (response -> 'order' ->> 'id')::uuid;
end;
$$;

do $$
declare
  test product_behavior_context%rowtype;
  untracked_item public.order_items%rowtype;
  untracked_order public.orders%rowtype;
begin
  select * into test from product_behavior_context;

  select oi.*
  into untracked_item
  from public.order_items oi
  where oi.order_id = test.untracked_order_id;

  if untracked_item.stock_tracking_enabled_snapshot
    or untracked_item.units_per_box_snapshot <> 24
    or untracked_item.retail_unit_price_snapshot <> 8
  then
    raise exception 'Untracked order snapshots were not preserved';
  end if;

  select o.*
  into untracked_order
  from public.orders o
  where o.id = test.untracked_order_id;

  if untracked_item.unit_price <> 50
    or untracked_item.line_total <> 250
    or untracked_order.subtotal <> 250
  then
    raise exception
      'Retail reference price affected authoritative wholesale totals';
  end if;

  if (
    select count(*)
    from public.inventory_reservations r
    where r.order_id = test.untracked_order_id
      and r.status = 'active'
  ) <> 1 then
    raise exception 'Untracked order must retain one auditable reservation';
  end if;

  begin
    update public.products
    set stock_tracking_enabled = false
    where id = test.tracked_product_id;
    raise exception
      'Tracked product allowed disabling with an active tracked reservation';
  exception
    when others then
      if sqlerrm <> 'STOCK_TRACKING_HAS_ACTIVE_RESERVATIONS' then
        raise;
      end if;
  end;
end;
$$;

do $$
declare
  test product_behavior_context%rowtype;
  untracked_initial_stock integer;
  tracked_initial_stock integer;
begin
  select * into test from product_behavior_context;

  select p.stock_quantity
  into untracked_initial_stock
  from public.products p
  where p.id = test.untracked_product_id;

  select p.stock_quantity
  into tracked_initial_stock
  from public.products p
  where p.id = test.tracked_product_id;

  perform public.transition_order_status_transaction(
    current_setting('test.admin_profile_id')::uuid,
    test.untracked_order_id,
    'confirmed',
    null
  );
  perform public.transition_order_status_transaction(
    current_setting('test.admin_profile_id')::uuid,
    test.untracked_order_id,
    'preparing',
    null
  );
  perform public.transition_order_status_transaction(
    current_setting('test.admin_profile_id')::uuid,
    test.untracked_order_id,
    'ready',
    null
  );
  perform public.transition_order_status_transaction(
    current_setting('test.admin_profile_id')::uuid,
    test.untracked_order_id,
    'delivered',
    null
  );

  if (
    select p.stock_quantity
    from public.products p
    where p.id = test.untracked_product_id
  ) <> untracked_initial_stock then
    raise exception 'Untracked delivery changed physical stock';
  end if;

  if (
    select count(*)
    from public.inventory_movements m
    where m.order_id = test.untracked_order_id
  ) <> 0 then
    raise exception 'Untracked delivery created a stock movement';
  end if;

  if (
    select count(*)
    from public.inventory_reservations r
    where r.order_id = test.untracked_order_id
      and r.status = 'fulfilled'
  ) <> 1 then
    raise exception 'Untracked delivery did not fulfill its reservation';
  end if;

  perform public.transition_order_status_transaction(
    current_setting('test.admin_profile_id')::uuid,
    test.tracked_order_id,
    'confirmed',
    null
  );
  perform public.transition_order_status_transaction(
    current_setting('test.admin_profile_id')::uuid,
    test.tracked_order_id,
    'preparing',
    null
  );
  perform public.transition_order_status_transaction(
    current_setting('test.admin_profile_id')::uuid,
    test.tracked_order_id,
    'ready',
    null
  );
  perform public.transition_order_status_transaction(
    current_setting('test.admin_profile_id')::uuid,
    test.tracked_order_id,
    'delivered',
    null
  );

  if (
    select p.stock_quantity
    from public.products p
    where p.id = test.tracked_product_id
  ) <> tracked_initial_stock - 5 then
    raise exception 'Tracked delivery did not decrement stock by five';
  end if;

  if (
    select count(*)
    from public.inventory_movements m
    where m.order_id = test.tracked_order_id
      and m.movement_type = 'sale'
      and m.quantity = -5
  ) <> 1 then
    raise exception 'Tracked delivery did not create one sale movement';
  end if;

  if (
    select count(*)
    from public.inventory_reservations r
    where r.order_id = test.tracked_order_id
      and r.status = 'fulfilled'
  ) <> 1 then
    raise exception 'Tracked delivery did not fulfill its reservation';
  end if;
end;
$$;

rollback;
