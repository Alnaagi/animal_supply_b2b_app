\set ON_ERROR_STOP on

begin;

do $$
declare
  bad_format_count integer;
  duplicated_count integer;
begin
  with generated as (
    select public.generate_public_order_number() as ref
    from generate_series(1, 2000)
  )
  select count(*)
  into bad_format_count
  from generated
  where ref !~ '^AS-[A-HJ-NP-Z2-9]{7}$';

  if bad_format_count <> 0 then
    raise exception 'Expected 0 bad formats, found %', bad_format_count;
  end if;

  with generated as (
    select public.generate_public_order_number() as ref
    from generate_series(1, 2000)
  )
  select count(*)
  into duplicated_count
  from (
    select ref
    from generated
    group by ref
    having count(*) > 1
  ) duplicates;

  if duplicated_count <> 0 then
    raise exception 'Expected no duplicates in sample, found %',
      duplicated_count;
  end if;
end;
$$;

do $$
begin
  if public.normalize_order_reference('AS-K7M4Q2P') <> 'AS-K7M4Q2P' then
    raise exception 'Canonical reference normalization failed';
  end if;
  if public.normalize_order_reference('as-k7m4q2p') <> 'AS-K7M4Q2P' then
    raise exception 'Lowercase normalization failed';
  end if;
  if public.normalize_order_reference('K7M4Q2P') <> 'AS-K7M4Q2P' then
    raise exception 'Prefix-less normalization failed';
  end if;
  if public.normalize_order_reference('AS-ABCD0EF') is not null then
    raise exception 'Ambiguous digit 0 should be rejected';
  end if;
  if public.normalize_order_reference('AS-ABCD1EF') is not null then
    raise exception 'Ambiguous digit 1 should be rejected';
  end if;
  if public.normalize_order_reference('AS-ABCDIEF') is not null then
    raise exception 'Ambiguous letter I should be rejected';
  end if;
  if public.normalize_order_reference('AS-20260819-000001')
    <> 'AS-20260819-000001' then
    raise exception 'Legacy sequential reference normalization failed';
  end if;
  if public.normalize_order_reference('as-20260819-000001')
    <> 'AS-20260819-000001' then
    raise exception 'Legacy lowercase normalization failed';
  end if;
  if public.normalize_order_reference('20260819000001')
    <> 'AS-20260819-000001' then
    raise exception 'Legacy prefix-less normalization failed';
  end if;
end;
$$;

rollback;
