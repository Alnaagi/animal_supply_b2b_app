-- Allow staff/admins to edit the complete set of mutable order fields in one
-- transaction. Product and quantity edits rebuild the exact reservation row so
-- the composite order-item/reservation identity remains valid.

create or replace function public.admin_update_order_transaction(
  p_actor_id uuid,
  p_order_id uuid,
  p_items jsonb,
  p_delivery_fee numeric,
  p_discount_amount numeric,
  p_admin_note text default null,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_role text;
  current_order public.orders%rowtype;
  old_item public.order_items%rowtype;
  target_product public.products%rowtype;
  submitted jsonb;
  target_product_id uuid;
  target_quantity integer;
  target_unit_price numeric(12, 2);
  item_count integer;
  expected_count integer;
  reservation_count integer;
  new_subtotal numeric(12, 2);
  changed boolean := false;
  changed_fields jsonb := '[]'::jsonb;
  line_changes jsonb := '[]'::jsonb;
  item_changed boolean;
  price_changed boolean;
  product_changed boolean;
  quantity_changed boolean;
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
    or round(p_delivery_fee, 2) <> p_delivery_fee
  then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_PRICING_INVALID';
  end if;

  if p_discount_amount is null
    or p_discount_amount < 0
    or p_discount_amount > 1000000
    or round(p_discount_amount, 2) <> p_discount_amount
  then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_PRICING_INVALID';
  end if;

  if p_admin_note is not null and length(p_admin_note) > 1000 then
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

  perform public.assert_fresh_updated_at(
    current_order.updated_at,
    p_expected_updated_at
  );

  if current_order.status in ('delivered', 'cancelled') then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_PRICING_LOCKED';
  end if;

  perform 1
  from public.order_items oi
  where oi.order_id = current_order.id
  for update;

  select count(*)
  into expected_count
  from public.order_items oi
  where oi.order_id = current_order.id;

  select count(*)
  into item_count
  from jsonb_array_elements(p_items);

  if item_count <> expected_count or expected_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_ITEM_MISMATCH';
  end if;

  if (
    select count(distinct (item ->> 'id')::uuid)
    from jsonb_array_elements(p_items) as item
  ) <> expected_count
  then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_ITEM_MISMATCH';
  end if;

  -- Lock target products in a stable order before validating or changing
  -- reservations. This prevents two concurrent admin edits from deadlocking
  -- when they touch the same products in a different line order.
  for target_product_id in
    select distinct coalesce(
      nullif(item ->> 'product_id', '')::uuid,
      oi.product_id
    )
    from jsonb_array_elements(p_items) as item
    join public.order_items oi
      on oi.id = (item ->> 'id')::uuid
      and oi.order_id = current_order.id
    order by 1
  loop
    perform 1
    from public.products p
    where p.id = target_product_id
    for update;
  end loop;

  for old_item in
    select oi.*
    from public.order_items oi
    where oi.order_id = current_order.id
    order by oi.id
  loop
    select value
    into submitted
    from jsonb_array_elements(p_items) as value
    where (value ->> 'id')::uuid = old_item.id;

    if submitted is null then
      raise exception using
        errcode = 'P0001',
        message = 'ORDER_ITEM_MISMATCH';
    end if;

    target_product_id := coalesce(
      nullif(submitted ->> 'product_id', '')::uuid,
      old_item.product_id
    );
    target_quantity := coalesce(
      nullif(submitted ->> 'quantity', '')::integer,
      old_item.quantity
    );
    target_unit_price := nullif(
      submitted ->> 'unit_price',
      ''
    )::numeric;

    if target_unit_price is null
      or target_unit_price < 0
      or target_unit_price > 1000000
      or round(target_unit_price, 2) <> target_unit_price
      or target_quantity < 1
      or target_quantity > 1000000
    then
      raise exception using
        errcode = 'P0001',
        message = 'ORDER_PRICING_INVALID';
    end if;

    select p.*
    into target_product
    from public.products p
    where p.id = target_product_id;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'PRODUCT_UNAVAILABLE',
        detail = target_product_id::text;
    end if;

    product_changed := target_product_id is distinct from old_item.product_id;
    quantity_changed := target_quantity is distinct from old_item.quantity;
    price_changed := target_unit_price is distinct from old_item.unit_price;
    item_changed := product_changed or quantity_changed or price_changed;

    if (product_changed or quantity_changed)
      and target_quantity < target_product.min_order_quantity
    then
      raise exception using
        errcode = 'P0001',
        message = 'MINIMUM_QUANTITY_NOT_MET',
        detail = jsonb_build_object(
          'product_id', target_product.id,
          'minimum_quantity', target_product.min_order_quantity,
          'requested_quantity', target_quantity
        )::text;
    end if;

    if product_changed
      and (
        not target_product.active
        or target_product.archived_at is not null
      )
    then
      raise exception using
        errcode = 'P0001',
        message = 'PRODUCT_UNAVAILABLE',
        detail = target_product.id::text;
    end if;

    if product_changed or quantity_changed then
      select count(*)
      into reservation_count
      from public.inventory_reservations r
      where r.order_id = current_order.id
        and r.order_item_id = old_item.id
        and r.status = 'active';

      if reservation_count <> 1 then
        raise exception using
          errcode = 'P0001',
          message = 'ORDER_RESERVATION_INCOMPLETE',
          detail = old_item.id::text;
      end if;

      if target_product.stock_tracking_enabled then
        select coalesce(sum(r.quantity), 0)::integer
        into reservation_count
        from public.inventory_reservations r
        join public.order_items oi
          on oi.id = r.order_item_id
          and oi.order_id = r.order_id
          and oi.product_id = r.product_id
          and oi.quantity = r.quantity
        where r.product_id = target_product.id
          and r.status = 'active'
          and not (
            r.order_id = current_order.id
            and r.order_item_id = old_item.id
          )
          and oi.stock_tracking_enabled_snapshot;

        if target_product.stock_quantity - reservation_count < target_quantity then
          raise exception using
            errcode = 'P0001',
            message = 'INSUFFICIENT_STOCK',
            detail = jsonb_build_object(
              'product_id', target_product.id,
              'available_quantity',
              greatest(target_product.stock_quantity - reservation_count, 0),
              'requested_quantity', target_quantity
            )::text;
        end if;
      end if;

      delete from public.inventory_reservations
      where order_item_id = old_item.id
        and order_id = current_order.id
        and status = 'active';

      update public.order_items
      set
        product_id = target_product.id,
        product_name_snapshot = target_product.name,
        product_sku_snapshot = target_product.sku,
        unit_size_snapshot = coalesce(target_product.unit_size, ''),
        package_label_snapshot = coalesce(
          nullif(target_product.package_size, ''),
          nullif(target_product.unit_size, ''),
          ''
        ),
        units_per_box_snapshot = target_product.units_per_box,
        retail_unit_price_snapshot = target_product.retail_unit_price,
        stock_tracking_enabled_snapshot = target_product.stock_tracking_enabled,
        quantity = target_quantity,
        unit_price = round(target_unit_price, 2)
      where id = old_item.id
        and order_id = current_order.id;

      insert into public.inventory_reservations (
        order_id,
        order_item_id,
        product_id,
        quantity,
        status
      )
      values (
        current_order.id,
        old_item.id,
        target_product.id,
        target_quantity,
        'active'
      );
    elsif price_changed then
      update public.order_items
      set unit_price = round(target_unit_price, 2)
      where id = old_item.id
        and order_id = current_order.id;
    end if;

    if item_changed then
      changed := true;
      line_changes := line_changes || jsonb_build_array(
        jsonb_build_object(
          'item_id', old_item.id,
          'product_changed', product_changed,
          'quantity_changed', quantity_changed,
          'price_changed', price_changed,
          'from_product_id', old_item.product_id,
          'to_product_id', target_product.id,
          'from_quantity', old_item.quantity,
          'to_quantity', target_quantity,
          'from_unit_price', old_item.unit_price,
          'to_unit_price', round(target_unit_price, 2)
        )
      );
    end if;
  end loop;

  select coalesce(sum(oi.line_total), 0)::numeric(12, 2)
  into new_subtotal
  from public.order_items oi
  where oi.order_id = current_order.id;

  if p_discount_amount > new_subtotal then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_DISCOUNT_INVALID';
  end if;

  if new_subtotal is distinct from current_order.subtotal then
    changed := true;
    changed_fields := changed_fields || jsonb_build_array('items');
  end if;
  if p_delivery_fee is distinct from current_order.delivery_fee then
    changed := true;
    changed_fields := changed_fields || jsonb_build_array('delivery_fee');
  end if;
  if p_discount_amount is distinct from current_order.discount_amount then
    changed := true;
    changed_fields := changed_fields || jsonb_build_array('discount_amount');
  end if;
  if p_admin_note is not null
    and nullif(btrim(p_admin_note), '') is distinct from current_order.admin_note
  then
    changed := true;
    changed_fields := changed_fields || jsonb_build_array('admin_note');
  end if;

  update public.orders
  set
    subtotal = new_subtotal,
    delivery_fee = p_delivery_fee,
    discount_amount = p_discount_amount,
    admin_note = case
      when p_admin_note is null then admin_note
      else nullif(btrim(p_admin_note), '')
    end
  where id = current_order.id;

  if current_order.customer_profile_id is not null and changed then
    perform public.enqueue_notification(
      current_order.customer_profile_id,
      'customer',
      'order_updated_by_admin',
      'تم تحديث طلبك من الإدارة',
      'تم تعديل تفاصيل الطلب ' || current_order.order_number
        || '. افتح الطلب لمراجعة المنتجات والمبلغ والملاحظة.',
      jsonb_build_object(
        'order_id', current_order.id,
        'order_number', current_order.order_number,
        'type', 'order_updated_by_admin',
        'changed_fields', changed_fields,
        'line_changes', line_changes,
        'admin_note', case
          when p_admin_note is null then current_order.admin_note
          else nullif(btrim(p_admin_note), '')
        end
      ),
      'order:admin_update:' || current_order.id::text || ':' || gen_random_uuid()::text
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
    'order.admin_updated',
    'orders',
    current_order.id,
    jsonb_build_object(
      'actor_role', actor_role,
      'order_number', current_order.order_number,
      'changed', changed,
      'changed_fields', changed_fields,
      'line_changes', line_changes,
      'admin_note_changed', p_admin_note is not null
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

comment on function public.admin_update_order_transaction(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric,
  text,
  timestamptz
) is
  'Staff/admin order edit with atomic product, quantity, pricing, note, reservation, audit, and customer notification handling.';

revoke all on function public.admin_update_order_transaction(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric,
  text,
  timestamptz
) from public, anon, authenticated;

grant execute on function public.admin_update_order_transaction(
  uuid,
  uuid,
  jsonb,
  numeric,
  numeric,
  text,
  timestamptz
) to service_role;

notify pgrst, 'reload schema';
