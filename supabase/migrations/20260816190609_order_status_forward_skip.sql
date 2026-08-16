-- Allow staff to jump forward along the happy path when intermediate
-- workflow steps are hidden in device-local prefs. Cancel stays reachable
-- from every non-terminal status. Backward jumps remain rejected.
-- Privileged RPC stays service_role-only (Edge Function boundary unchanged).

create or replace function public.is_allowed_order_status_transition(
  p_from text,
  p_to text
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p_from is null or p_to is null then false
    when p_from = p_to then true
    when p_from in ('delivered', 'cancelled') then false
    when p_to = 'cancelled' then p_from in (
      'pending',
      'confirmed',
      'preparing',
      'ready'
    )
    when p_from = 'pending' then p_to in (
      'confirmed',
      'preparing',
      'ready',
      'delivered'
    )
    when p_from = 'confirmed' then p_to in (
      'preparing',
      'ready',
      'delivered'
    )
    when p_from = 'preparing' then p_to in ('ready', 'delivered')
    when p_from = 'ready' then p_to = 'delivered'
    else false
  end;
$$;

comment on function public.is_allowed_order_status_transition(text, text) is
  'Forward happy-path skips plus cancel from non-terminal statuses.';

revoke all on function public.is_allowed_order_status_transition(text, text)
  from public, anon, authenticated, service_role;

grant execute on function public.is_allowed_order_status_transition(text, text)
  to service_role;

create or replace function public.transition_order_status_transaction_unguarded(
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

  if not public.is_allowed_order_status_transition(
    current_order.status,
    p_status
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

comment on function public.transition_order_status_transaction_unguarded(
  uuid,
  uuid,
  text,
  text
) is
  'Authoritative staff transition with forward happy-path skips. Delivery fulfills reservations and deducts tracked stock; cancel releases active reservations.';

revoke all on function public.transition_order_status_transaction_unguarded(
  uuid,
  uuid,
  text,
  text
) from public, anon, authenticated, service_role;
