alter table profiles enable row level security;
alter table price_groups enable row level security;
alter table business_customers enable row level security;
alter table customer_contacts enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table product_images enable row level security;
alter table product_prices enable row level security;
alter table customer_special_prices enable row level security;
alter table inventory_movements enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table app_settings enable row level security;
alter table banners enable row level security;
alter table admin_device_tokens enable row level security;
alter table notifications enable row level security;
alter table app_versions enable row level security;
alter table invite_tokens enable row level security;
alter table audit_logs enable row level security;
alter table sync_outbox enable row level security;

create or replace function public.current_role()
returns text language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.current_role() = 'admin', false)
$$;

create or replace function public.is_staff_or_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.current_role() in ('admin','staff'), false)
$$;

create or replace function public.current_customer_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from business_customers where profile_id = auth.uid()
$$;

create policy "profiles self read" on profiles for select using (id = auth.uid() or public.is_staff_or_admin());
create policy "profiles admin manage" on profiles for all using (public.is_admin()) with check (public.is_admin());

create policy "price groups readable" on price_groups for select using (auth.uid() is not null and (active or public.is_staff_or_admin()));
create policy "price groups admin manage" on price_groups for all using (public.is_admin()) with check (public.is_admin());

create policy "customers own or staff" on business_customers for select using (profile_id = auth.uid() or public.is_staff_or_admin());
create policy "customers staff manage" on business_customers for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "contacts own or staff" on customer_contacts for select using (customer_id = public.current_customer_id() or public.is_staff_or_admin());
create policy "contacts staff manage" on customer_contacts for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "categories active readable" on categories for select using (auth.uid() is not null and (active or public.is_staff_or_admin()));
create policy "categories staff manage" on categories for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "products active readable" on products for select using (auth.uid() is not null and (active or public.is_staff_or_admin()));
create policy "products staff manage" on products for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "product images readable with products" on product_images for select using (
  exists (select 1 from products p where p.id = product_id and (p.active or public.is_staff_or_admin()))
);
create policy "product images staff manage" on product_images for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "product prices readable" on product_prices for select using (
  public.is_staff_or_admin()
  or exists (
    select 1
    from business_customers c
    where c.id = public.current_customer_id()
      and c.price_group_id = product_prices.price_group_id
  )
);
create policy "product prices staff manage" on product_prices for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "special prices scoped" on customer_special_prices for select using (customer_id = public.current_customer_id() or public.is_staff_or_admin());
create policy "special prices staff manage" on customer_special_prices for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "inventory staff only" on inventory_movements for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "orders own or staff read" on orders for select using (customer_id = public.current_customer_id() or public.is_staff_or_admin());
create policy "customers create own orders" on orders for insert with check (customer_id = public.current_customer_id());
create policy "staff manage orders" on orders for update using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "order items own or staff read" on order_items for select using (
  exists (select 1 from orders o where o.id = order_id and (o.customer_id = public.current_customer_id() or public.is_staff_or_admin()))
);
create policy "customers insert own order items" on order_items for insert with check (
  exists (select 1 from orders o where o.id = order_id and o.customer_id = public.current_customer_id())
);
create policy "staff manage order items" on order_items for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "settings readable" on app_settings for select using (auth.uid() is not null);
create policy "settings admin manage" on app_settings for all using (public.is_admin()) with check (public.is_admin());

create policy "banners readable" on banners for select using (active or public.is_staff_or_admin());
create policy "banners staff manage" on banners for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

create policy "device tokens owner or staff" on admin_device_tokens for select using (profile_id = auth.uid() or public.is_staff_or_admin());
create policy "device tokens owner insert" on admin_device_tokens for insert with check (profile_id = auth.uid() and public.is_staff_or_admin());
create policy "device tokens owner update" on admin_device_tokens for update using (profile_id = auth.uid() or public.is_staff_or_admin()) with check (profile_id = auth.uid() or public.is_staff_or_admin());

create policy "notifications scoped read" on notifications for select using (
  recipient_profile_id = auth.uid()
  or (recipient_role = public.current_role())
  or public.is_staff_or_admin()
);
create policy "notifications staff insert" on notifications for insert with check (public.is_staff_or_admin());
create policy "notifications own mark read" on notifications for update using (recipient_profile_id = auth.uid() or public.is_staff_or_admin()) with check (recipient_profile_id = auth.uid() or public.is_staff_or_admin());

create policy "app versions readable" on app_versions for select using (published or public.is_staff_or_admin());
create policy "app versions admin manage" on app_versions for all using (public.is_admin()) with check (public.is_admin());

create policy "invite tokens staff only" on invite_tokens for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());
create policy "audit logs admin read" on audit_logs for select using (public.is_admin());
create policy "audit logs staff insert" on audit_logs for insert with check (public.is_staff_or_admin());
create policy "sync outbox own" on sync_outbox for all using (owner_id = auth.uid() or public.is_staff_or_admin()) with check (owner_id = auth.uid() or public.is_staff_or_admin());
