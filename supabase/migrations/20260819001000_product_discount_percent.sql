-- Add NOT NULL constraint and check to products.discount_percent (column already exists as integer nullable).
-- Existing rows default to 0; new rows default to 0; range 0–100.

set session_replication_role = replica;
update public.products
  set discount_percent = 0
  where discount_percent is null;
set session_replication_role = default;

alter table public.products
  alter column discount_percent set default 0,
  alter column discount_percent set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'products_discount_percent_range'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_discount_percent_range
      check (discount_percent >= 0 and discount_percent <= 100);
  end if;
end;
$$;

comment on column public.products.discount_percent is
  'Product-level discount percentage shown to customers (0 = no discount, 1–100 = % off base price).';
