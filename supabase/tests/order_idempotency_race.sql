\set ON_ERROR_STOP on

-- Manual two-session verification for place_order_transaction concurrency.
--
-- Required psql variables:
--   actor_id   UUID of an active customer profile
--   request_id A fresh UUID shared by both sessions
--   items      JSON array such as [{"product_id":"UUID","quantity":2}]
--
-- Open two terminals. Start SESSION A, then start SESSION B while SESSION A is
-- sleeping. After both finish, run ASSERTIONS. Use the same actor_id,
-- request_id, and items values for all three commands:
--
--   psql "$DATABASE_URL" -f supabase/tests/order_idempotency_race.sql \
--     -v session_a=1 -v actor_id=... -v request_id=... \
--     -v items='[{"product_id":"...","quantity":2}]'
--
--   psql "$DATABASE_URL" -f supabase/tests/order_idempotency_race.sql \
--     -v session_b=1 -v actor_id=... -v request_id=... \
--     -v items='[{"product_id":"...","quantity":2}]'
--
--   psql "$DATABASE_URL" -f supabase/tests/order_idempotency_race.sql \
--     -v assertions=1 -v actor_id=... -v request_id=... \
--     -v items='[{"product_id":"...","quantity":2}]'
--
--   psql "$DATABASE_URL" -f supabase/tests/order_idempotency_race.sql \
--     -v conflict=1 -v actor_id=... -v request_id=... \
--     -v items='[{"product_id":"...","quantity":2}]'
--
-- SESSION B must wait, then return the same order id with "idempotent": true
-- after SESSION A commits. CONFLICT reuses the idempotency key with a changed
-- note and must fail with IDEMPOTENCY_CONFLICT.

-- SESSION A
\if :{?session_a}
begin;

create temporary table order_idempotency_session_result (
  payload jsonb not null
) on commit drop;

insert into order_idempotency_session_result (payload)
select public.place_order_transaction(
  :'actor_id'::uuid,
  :'request_id'::uuid,
  :'items'::jsonb,
  'عنوان اختبار سباق التكرار',
  'اختبار التزامن',
  null
);

select payload as session_a_result
from order_idempotency_session_result;

do $$
declare
  is_idempotent boolean;
begin
  select coalesce((payload->>'idempotent')::boolean, true)
  into is_idempotent
  from order_idempotency_session_result;

  if is_idempotent then
    raise exception 'SESSION A expected a new, non-idempotent order';
  end if;
end;
$$;

select pg_sleep(10);

commit;
\endif

-- SESSION B (run in a separate connection during SESSION A's sleep)
\if :{?session_b}
begin;

create temporary table order_idempotency_session_result (
  payload jsonb not null
) on commit drop;

insert into order_idempotency_session_result (payload)
select public.place_order_transaction(
  :'actor_id'::uuid,
  :'request_id'::uuid,
  :'items'::jsonb,
  'عنوان اختبار سباق التكرار',
  'اختبار التزامن',
  null
);

select payload as session_b_result
from order_idempotency_session_result;

do $$
declare
  is_idempotent boolean;
begin
  select coalesce((payload->>'idempotent')::boolean, false)
  into is_idempotent
  from order_idempotency_session_result;

  if not is_idempotent then
    raise exception 'SESSION B expected the committed idempotent order';
  end if;
end;
$$;

commit;
\endif

-- ASSERTIONS (run after both sessions finish)
\if :{?assertions}
begin;

create temporary table order_idempotency_race_context (
  actor_id uuid not null,
  request_id uuid not null
) on commit drop;

insert into order_idempotency_race_context (actor_id, request_id)
values (:'actor_id'::uuid, :'request_id'::uuid);

do $$
declare
  matching_orders integer;
  matching_item_sets integer;
  matching_reservation_sets integer;
  matching_fingerprints integer;
begin
  select count(*)
  into matching_orders
  from public.orders o
  join public.business_customers c on c.id = o.customer_id
  cross join order_idempotency_race_context test
  where c.profile_id = test.actor_id
    and o.client_request_id = test.request_id;

  select count(distinct oi.order_id)
  into matching_item_sets
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  join public.business_customers c on c.id = o.customer_id
  cross join order_idempotency_race_context test
  where c.profile_id = test.actor_id
    and o.client_request_id = test.request_id;

  select count(distinct r.order_id)
  into matching_reservation_sets
  from public.inventory_reservations r
  join public.orders o on o.id = r.order_id
  join public.business_customers c on c.id = o.customer_id
  cross join order_idempotency_race_context test
  where c.profile_id = test.actor_id
    and o.client_request_id = test.request_id;

  select count(*)
  into matching_fingerprints
  from public.orders o
  join public.business_customers c on c.id = o.customer_id
  cross join order_idempotency_race_context test
  where c.profile_id = test.actor_id
    and o.client_request_id = test.request_id
    and o.request_fingerprint ~ '^[0-9a-f]{64}$';

  if matching_orders <> 1 then
    raise exception 'Expected one order, found %', matching_orders;
  end if;

  if matching_item_sets <> 1 then
    raise exception 'Expected one order item set, found %', matching_item_sets;
  end if;

  if matching_reservation_sets <> 1 then
    raise exception 'Expected one reservation set, found %',
      matching_reservation_sets;
  end if;

  if matching_fingerprints <> 1 then
    raise exception 'Expected one canonical request fingerprint, found %',
      matching_fingerprints;
  end if;
end;
$$;

commit;
\endif

-- CHANGED-PAYLOAD CONFLICT (run after SESSION A/B)
\if :{?conflict}
begin;

create temporary table order_idempotency_conflict_context (
  actor_id uuid not null,
  request_id uuid not null,
  items jsonb not null
) on commit drop;

insert into order_idempotency_conflict_context (
  actor_id,
  request_id,
  items
)
values (
  :'actor_id'::uuid,
  :'request_id'::uuid,
  :'items'::jsonb
);

do $$
declare
  test order_idempotency_conflict_context%rowtype;
  error_message text;
begin
  select *
  into test
  from order_idempotency_conflict_context;

  begin
    perform public.place_order_transaction(
      test.actor_id,
      test.request_id,
      test.items,
      'عنوان اختبار سباق التكرار',
      'ملاحظة مختلفة يجب رفضها',
      null
    );
    raise exception 'Expected IDEMPOTENCY_CONFLICT';
  exception
    when sqlstate 'P0001' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'IDEMPOTENCY_CONFLICT' then
        raise exception 'Expected IDEMPOTENCY_CONFLICT, got %',
          error_message;
      end if;
  end;
end;
$$;

commit;
\endif
