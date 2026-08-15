-- Serialize retries for the same customer request before running the existing
-- authoritative order transaction.
--
-- The existing implementation already locks the business_customers row. This
-- wrapper adds a request-scoped transaction advisory lock so the idempotency
-- guarantee is explicit and remains safe if the broader customer-row lock is
-- ever narrowed. A concurrent retry waits for the first transaction to commit
-- or roll back; after a commit, the existing implementation returns the
-- committed order with idempotent = true.

alter function public.place_order_transaction(
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) rename to place_order_transaction_impl;

create function public.place_order_transaction(
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
set search_path = public
as $$
begin
  -- Let the implementation preserve the established validation errors for
  -- missing identifiers instead of changing the public RPC contract here.
  if p_actor_id is not null and p_client_request_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        p_actor_id::text || ':' || p_client_request_id::text,
        0
      )
    );
  end if;

  return public.place_order_transaction_impl(
    p_actor_id,
    p_client_request_id,
    p_items,
    p_delivery_address,
    p_customer_note,
    p_delivery_note
  );
end;
$$;

-- Only the stable public RPC is callable by the Edge Function service role.
-- The implementation remains owner-only so callers cannot bypass the lock.
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
) from public, anon, authenticated;

grant execute on function public.place_order_transaction(
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) to service_role;

notify pgrst, 'reload schema';
