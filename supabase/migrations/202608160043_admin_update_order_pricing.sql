alter table public.orders
  add column if not exists discount_amount numeric(12, 2) not null default 0;

do $$
declare
  constraint_name text;
begin
  select con.conname
  into constraint_name
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname = 'orders'
    and con.contype = 'c'
    and pg_get_constraintdef(con.oid) ilike '%delivery_fee%'
    and pg_get_constraintdef(con.oid) ilike '%handling_fee%'
    and pg_get_constraintdef(con.oid) not ilike '%discount_amount%';
  if constraint_name is not null then
    execute format(
      'alter table public.orders drop constraint %I',
      constraint_name
    );
  end if;
end
$$;

alter table public.orders
  drop column if exists total;

alter table public.orders
  add column total numeric(12, 2)
  generated always as (
    subtotal + delivery_fee + handling_fee - discount_amount
  ) stored;

alter table public.orders
  drop constraint if exists orders_money_nonnegative;

alter table public.orders
  add constraint orders_money_nonnegative
  check (
    subtotal >= 0
    and delivery_fee >= 0
    and handling_fee >= 0
    and discount_amount >= 0
    and discount_amount <= subtotal
  );

comment on column public.orders.discount_amount is
  'Staff-approved order discount in LYD. Total is subtotal + delivery + handling - discount.';

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
    'discount_amount', o.discount_amount,
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

create or replace function public.admin_update_order_pricing_transaction(
  p_actor_id uuid,
  p_order_id uuid,
  p_items jsonb,
  p_delivery_fee numeric,
  p_discount_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_role text;
  current_order public.orders%rowtype;
  item_count integer;
  expected_count integer;
  new_subtotal numeric(12, 2);
  item_row record;
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

  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception using
      errcode = 'P0001',
      message = 'INVALID_ORDER_ITEM';
  end if;

  if p_delivery_fee is null
    or p_delivery_fee < 0
    or p_delivery_fee > 1000000
    or round(p_delivery_fee, 2) <> p_delivery_fee then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_PRICING_INVALID';
  end if;

  if p_discount_amount is null
    or p_discount_amount < 0
    or p_discount_amount > 1000000
    or round(p_discount_amount, 2) <> p_discount_amount then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_PRICING_INVALID';
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

  if current_order.status in ('delivered', 'cancelled') then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_PRICING_LOCKED';
  end if;

  select count(*)
  into expected_count
  from public.order_items
  where order_id = current_order.id;

  select count(*)
  into item_count
  from jsonb_array_elements(p_items) as item;

  if item_count <> expected_count or expected_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_ITEM_MISMATCH';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) as item
    where nullif(item ->> 'id', '') is null
      or (item ->> 'id')::uuid is null
      or not exists (
        select 1
        from public.order_items oi
        where oi.id = (item ->> 'id')::uuid
          and oi.order_id = current_order.id
      )
      or coalesce(item ->> 'unit_price', '') = ''
      or (item ->> 'unit_price')::numeric < 0
      or (item ->> 'unit_price')::numeric > 1000000
      or round((item ->> 'unit_price')::numeric, 2)
        <> (item ->> 'unit_price')::numeric
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_PRICING_INVALID';
  end if;

  if (
    select count(distinct (item ->> 'id')::uuid)
    from jsonb_array_elements(p_items) as item
  ) <> expected_count then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_ITEM_MISMATCH';
  end if;

  for item_row in
    select
      (item ->> 'id')::uuid as id,
      (item ->> 'unit_price')::numeric(12, 2) as unit_price
    from jsonb_array_elements(p_items) as item
  loop
    update public.order_items
    set unit_price = item_row.unit_price
    where id = item_row.id
      and order_id = current_order.id;
  end loop;

  select coalesce(sum(oi.line_total), 0)
  into new_subtotal
  from public.order_items oi
  where oi.order_id = current_order.id;

  if p_discount_amount > new_subtotal then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_DISCOUNT_INVALID';
  end if;

  update public.orders
  set
    subtotal = new_subtotal,
    delivery_fee = p_delivery_fee,
    discount_amount = p_discount_amount
  where id = current_order.id;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    p_actor_id,
    'order.pricing_updated',
    'orders',
    current_order.id,
    jsonb_build_object(
      'actor_role', actor_role,
      'order_number', current_order.order_number,
      'subtotal', jsonb_build_object(
        'from', current_order.subtotal,
        'to', new_subtotal
      ),
      'delivery_fee', jsonb_build_object(
        'from', current_order.delivery_fee,
        'to', p_delivery_fee
      ),
      'discount_amount', jsonb_build_object(
        'from', current_order.discount_amount,
        'to', p_discount_amount
      )
    )
  );

  return jsonb_build_object(
    'order', public.order_payload(current_order.id)
      || jsonb_build_object(
        'status_history',
        public.order_status_history_payload(current_order.id)
      )
  );
end;
$$;

comment on function public.admin_update_order_pricing_transaction(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric
) is
  'Staff/admin order pricing update. Callable solely by service_role from admin-update-order-pricing.';

revoke all on function public.admin_update_order_pricing_transaction(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric
) from public, anon, authenticated;
grant execute on function public.admin_update_order_pricing_transaction(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric
) to service_role;
