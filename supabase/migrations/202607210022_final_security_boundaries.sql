-- Close the remaining direct-client authorization gaps and prevent legacy
-- orders without complete reservations from advancing through fulfillment.

create or replace function public.current_role()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
    and p.active
    and not p.must_change_password
    and (
      p.role in ('admin', 'staff')
      or (
        p.role = 'customer'
        and exists (
          select 1
          from public.business_customers c
          where c.profile_id = p.id
            and c.account_status = 'active'
            and c.archived_at is null
        )
      )
    )
$$;

create or replace function public.is_active_actor()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.current_role() is not null
$$;

create or replace function public.current_customer_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.id
  from public.business_customers c
  join public.profiles p on p.id = c.profile_id
  where c.profile_id = auth.uid()
    and p.active
    and not p.must_change_password
    and p.role = 'customer'
    and c.account_status = 'active'
    and c.archived_at is null
$$;

-- Profiles remain self-readable so the app can discover the forced-password
-- flag. All mutations are privileged server operations.
drop policy if exists "profiles admin manage" on public.profiles;
revoke insert, update, delete on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;

-- The legacy admin-device table is no longer a client write path.
drop policy if exists "admin device tokens owner read"
  on public.admin_device_tokens;
drop policy if exists "admin device tokens owner insert"
  on public.admin_device_tokens;
drop policy if exists "admin device tokens owner update"
  on public.admin_device_tokens;
revoke all on public.admin_device_tokens from anon, authenticated;

drop policy if exists "notifications scoped read" on public.notifications;
create policy "notifications scoped read"
on public.notifications
for select
using (
  recipient_profile_id = auth.uid()
  and public.is_active_actor()
);

drop policy if exists "notifications own mark read" on public.notifications;
create policy "notifications own mark read"
on public.notifications
for update
using (
  recipient_profile_id = auth.uid()
  and public.is_active_actor()
)
with check (
  recipient_profile_id = auth.uid()
  and public.is_active_actor()
);

drop policy if exists "sync outbox own" on public.sync_outbox;
create policy "sync outbox own"
on public.sync_outbox
for all
using (
  owner_id = auth.uid()
  and public.is_active_actor()
)
with check (
  owner_id = auth.uid()
  and public.is_active_actor()
);

create or replace function public.enforce_order_reservation_integrity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  expected_reservation_status text;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  expected_reservation_status := case
    when new.status in ('confirmed', 'preparing', 'ready') then 'active'
    when new.status = 'delivered' then 'fulfilled'
    else null
  end;

  if expected_reservation_status is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.order_items oi
    where oi.order_id = new.id
  ) or exists (
    select 1
    from public.order_items oi
    left join public.inventory_reservations r
      on r.order_item_id = oi.id
      and r.order_id = oi.order_id
      and r.product_id = oi.product_id
      and r.status = expected_reservation_status
    where oi.order_id = new.id
    group by oi.id, oi.quantity
    having count(r.id) <> 1
      or coalesce(sum(r.quantity), 0) <> oi.quantity
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'ORDER_RESERVATION_INCOMPLETE',
      detail = new.id::text;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_order_reservation_integrity
  on public.orders;
create trigger enforce_order_reservation_integrity
before update of status on public.orders
for each row
execute function public.enforce_order_reservation_integrity();

create or replace function public.enforce_reserved_stock_floor()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_stock integer;
  active_reserved integer;
begin
  select p.stock_quantity
  into current_stock
  from public.products p
  where p.id = new.id;

  if current_stock is null then
    return new;
  end if;

  select coalesce(sum(r.quantity), 0)::integer
  into active_reserved
  from public.inventory_reservations r
  where r.product_id = new.id
    and r.status = 'active';

  if current_stock < active_reserved then
    raise exception using
      errcode = 'P0001',
      message = 'STOCK_BELOW_ACTIVE_RESERVATIONS',
      detail = jsonb_build_object(
        'product_id', new.id,
        'stock_quantity', current_stock,
        'active_reserved', active_reserved
      )::text;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_reserved_stock_floor
  on public.products;
create constraint trigger enforce_reserved_stock_floor
after update on public.products
deferrable initially deferred
for each row
execute function public.enforce_reserved_stock_floor();

notify pgrst, 'reload schema';
