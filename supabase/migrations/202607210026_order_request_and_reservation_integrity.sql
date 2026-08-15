-- Bind every order idempotency key to the canonical request that created it,
-- and ensure each reservation references the exact order-item identity.

begin;

alter table public.orders
  add column if not exists request_fingerprint text;

create or replace function public.canonical_order_request_fingerprint(
  p_items jsonb,
  p_delivery_address text,
  p_customer_note text,
  p_delivery_note text
)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  with normalized_items as (
    select
      parsed.product_id,
      sum(parsed.quantity)::integer as quantity
    from jsonb_to_recordset(p_items)
      as parsed(product_id uuid, quantity integer)
    group by parsed.product_id
  ),
  canonical_payload as (
    select jsonb_build_object(
      'items',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'product_id', item.product_id,
              'quantity', item.quantity
            )
            order by item.product_id
          )
          from normalized_items item
        ),
        '[]'::jsonb
      ),
      'delivery_address',
      coalesce(nullif(btrim(p_delivery_address), ''), ''),
      'customer_note',
      coalesce(nullif(btrim(p_customer_note), ''), ''),
      'delivery_note',
      coalesce(nullif(btrim(p_delivery_note), ''), '')
    ) as payload
  )
  select pg_catalog.encode(
    pg_catalog.sha256(
      pg_catalog.convert_to(payload::text, 'UTF8')
    ),
    'hex'
  )
  from canonical_payload
$$;

revoke all on function public.canonical_order_request_fingerprint(
  jsonb,
  text,
  text,
  text
) from public, anon, authenticated, service_role;

-- Existing rows cannot recover whether an address was omitted by the client,
-- so compatibility is based on the authoritative values persisted on the
-- order plus its aggregated item set.
update public.orders o
set request_fingerprint = public.canonical_order_request_fingerprint(
  coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'product_id', item.product_id,
          'quantity', item.quantity
        )
        order by item.product_id
      )
      from (
        select
          oi.product_id,
          sum(oi.quantity)::integer as quantity
        from public.order_items oi
        where oi.order_id = o.id
        group by oi.product_id
      ) item
    ),
    '[]'::jsonb
  ),
  o.delivery_address,
  o.customer_note,
  o.delivery_note
)
where o.request_fingerprint is null;

create or replace function public.apply_order_request_fingerprint()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' and new.request_fingerprint is null then
    new.request_fingerprint := nullif(
      current_setting('app.order_request_fingerprint', true),
      ''
    );
  end if;

  new.request_fingerprint := lower(new.request_fingerprint);
  if new.request_fingerprint is null
    or new.request_fingerprint !~ '^[0-9a-f]{64}$'
  then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_REQUEST_FINGERPRINT_REQUIRED';
  end if;

  return new;
end;
$$;

revoke all on function public.apply_order_request_fingerprint()
  from public, anon, authenticated, service_role;

drop trigger if exists apply_order_request_fingerprint_on_insert
  on public.orders;
create trigger apply_order_request_fingerprint_on_insert
before insert on public.orders
for each row
execute function public.apply_order_request_fingerprint();

drop trigger if exists validate_order_request_fingerprint_on_update
  on public.orders;
create trigger validate_order_request_fingerprint_on_update
before update of request_fingerprint on public.orders
for each row
execute function public.apply_order_request_fingerprint();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'orders_request_fingerprint_format'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders
      add constraint orders_request_fingerprint_format
      check (request_fingerprint ~ '^[0-9a-f]{64}$')
      not valid;
  end if;
end
$$;

alter table public.orders
  validate constraint orders_request_fingerprint_format;
alter table public.orders
  alter column request_fingerprint set not null;

comment on column public.orders.request_fingerprint is
  'SHA-256 of normalized items and persisted delivery/note request fields.';

create or replace function public.place_order_transaction(
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
  v_customer_id uuid;
  v_customer_address text;
  v_customer_status text;
  v_resolved_delivery_address text;
  v_request_fingerprint text;
  v_existing_order_id uuid;
  v_existing_fingerprint text;
  v_result_payload jsonb;
  v_result_order_id uuid;
begin
  -- Preserve the implementation's established validation errors for requests
  -- that cannot create an order.
  if p_actor_id is null
    or p_client_request_id is null
  then
    return public.place_order_transaction_impl(
      p_actor_id,
      p_client_request_id,
      p_items,
      p_delivery_address,
      p_customer_note,
      p_delivery_note
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || p_client_request_id::text,
      0
    )
  );

  if p_items is null
    or jsonb_typeof(p_items) <> 'array'
    or jsonb_array_length(p_items) = 0
    or jsonb_array_length(p_items) > 100
  then
    return public.place_order_transaction_impl(
      p_actor_id,
      p_client_request_id,
      p_items,
      p_delivery_address,
      p_customer_note,
      p_delivery_note
    );
  end if;

  select c.id, c.address, c.account_status
  into v_customer_id, v_customer_address, v_customer_status
  from public.business_customers c
  join public.profiles p on p.id = c.profile_id
  where p.id = p_actor_id
    and p.active
    and not p.must_change_password
    and p.role = 'customer'
  for update of c;

  if not found or v_customer_status <> 'active' then
    return public.place_order_transaction_impl(
      p_actor_id,
      p_client_request_id,
      p_items,
      p_delivery_address,
      p_customer_note,
      p_delivery_note
    );
  end if;

  v_resolved_delivery_address := coalesce(
    nullif(btrim(p_delivery_address), ''),
    nullif(btrim(v_customer_address), ''),
    ''
  );
  v_request_fingerprint := public.canonical_order_request_fingerprint(
    p_items,
    v_resolved_delivery_address,
    p_customer_note,
    p_delivery_note
  );

  select o.id, o.request_fingerprint
  into v_existing_order_id, v_existing_fingerprint
  from public.orders o
  where o.customer_id = v_customer_id
    and o.client_request_id = p_client_request_id;

  if found then
    if v_existing_fingerprint is distinct from v_request_fingerprint then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_CONFLICT',
        detail = p_client_request_id::text;
    end if;

    return jsonb_build_object(
      'order', public.order_payload(v_existing_order_id),
      'idempotent', true
    );
  end if;

  perform pg_catalog.set_config(
    'app.order_request_fingerprint',
    v_request_fingerprint,
    true
  );

  begin
    v_result_payload := public.place_order_transaction_impl(
      p_actor_id,
      p_client_request_id,
      p_items,
      p_delivery_address,
      p_customer_note,
      p_delivery_note
    );
  exception
    when others then
      perform pg_catalog.set_config(
        'app.order_request_fingerprint',
        '',
        true
      );
      raise;
  end;

  perform pg_catalog.set_config(
    'app.order_request_fingerprint',
    '',
    true
  );

  v_result_order_id := nullif(
    v_result_payload -> 'order' ->> 'id',
    ''
  )::uuid;
  if v_result_order_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_RESPONSE_INVALID';
  end if;

  select o.request_fingerprint
  into v_existing_fingerprint
  from public.orders o
  where o.id = v_result_order_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_RESPONSE_INVALID';
  end if;

  if v_existing_fingerprint is distinct from v_request_fingerprint then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_CONFLICT',
      detail = p_client_request_id::text;
  end if;

  return v_result_payload;
end;
$$;

revoke all on function public.place_order_transaction_impl(
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) from public, anon, authenticated, service_role;

revoke all on function public.place_order_transaction(
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) from public, anon, authenticated, service_role;

grant execute on function public.place_order_transaction(
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) to service_role;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'order_items_reservation_identity_unique'
      and conrelid = 'public.order_items'::regclass
  ) then
    alter table public.order_items
      add constraint order_items_reservation_identity_unique
      unique (id, order_id, product_id, quantity);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'inventory_reservations_order_item_identity_fkey'
      and conrelid = 'public.inventory_reservations'::regclass
  ) then
    alter table public.inventory_reservations
      add constraint inventory_reservations_order_item_identity_fkey
      foreign key (order_item_id, order_id, product_id, quantity)
      references public.order_items (id, order_id, product_id, quantity)
      on delete cascade
      not valid;
  end if;
end
$$;

alter table public.inventory_reservations
  validate constraint inventory_reservations_order_item_identity_fkey;

notify pgrst, 'reload schema';

commit;
