begin;

-- Supabase installs pgcrypto in the `extensions` schema. Keep it on
-- search_path (and prefer the schema-qualified call) so SECURITY INVOKER
-- functions with a locked search_path can still generate order numbers.
create extension if not exists pgcrypto with schema extensions;

create or replace function public.generate_public_order_number()
returns text
language plpgsql
volatile
security invoker
set search_path = public, extensions, pg_temp
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea := extensions.gen_random_bytes(7);
  v_token text := '';
  v_idx integer;
begin
  for v_idx in 0..6 loop
    v_token := v_token || substr(
      v_alphabet,
      (get_byte(v_bytes, v_idx) % 32) + 1,
      1
    );
  end loop;
  return 'AS-' || v_token;
end;
$$;

comment on function public.generate_public_order_number() is
  'Generates short public order references using cryptographic randomness (AS- + 7 chars from an ambiguity-safe alphabet).';

create or replace function public.normalize_order_reference(p_raw text)
returns text
language plpgsql
immutable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_clean text;
begin
  v_clean := upper(
    regexp_replace(
      coalesce(p_raw, ''),
      '[^A-Za-z0-9]',
      '',
      'g'
    )
  );
  if v_clean like 'AS%' then
    v_clean := substr(v_clean, 3);
  end if;
  -- Legacy sequential references stay canonical for lookup: AS-YYYYMMDD-NNNNNN.
  if v_clean ~ '^\d{14}$' then
    return 'AS-'
      || substr(v_clean, 1, 8)
      || '-'
      || substr(v_clean, 9, 6);
  end if;
  if length(v_clean) <> 7 then
    return null;
  end if;
  if v_clean !~ '^[A-HJ-NP-Z2-9]{7}$' then
    return null;
  end if;
  return 'AS-' || v_clean;
end;
$$;

comment on function public.normalize_order_reference(text) is
  'Normalizes customer/admin-entered order references to canonical AS-XXXXXXX form (case-insensitive, optional hyphens and optional AS prefix).';

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
  number_attempt integer;
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

  for number_attempt in 1..20 loop
    new_order_number := public.generate_public_order_number();
    begin
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
      exit;
    exception
      when unique_violation then
        if number_attempt = 20 then
          raise exception using
            errcode = 'P0001',
            message = 'ORDER_NUMBER_GENERATION_FAILED';
        end if;
    end;
  end loop;

  if new_order_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_NUMBER_GENERATION_FAILED';
  end if;

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

create index if not exists idx_orders_order_reference_normalized
  on public.orders (public.normalize_order_reference(order_number));

notify pgrst, 'reload schema';

commit;
