begin;

-- Production regression: generate_public_order_number() used gen_random_bytes()
-- while search_path was only `public, pg_temp`. On hosted Supabase, pgcrypto
-- lives in `extensions`, so place_order_transaction failed at order-number
-- generation and checkout showed a generic Arabic failure with the cart kept.

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

notify pgrst, 'reload schema';

commit;
