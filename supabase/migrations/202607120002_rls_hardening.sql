-- Replace permissive prototype policies with active-account, owner-scoped RLS.

alter table public.profiles enable row level security;
alter table public.price_groups enable row level security;
alter table public.business_customers enable row level security;
alter table public.customer_contacts enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.product_prices enable row level security;
alter table public.customer_special_prices enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_status_history enable row level security;
alter table public.inventory_reservations enable row level security;
alter table public.app_settings enable row level security;
alter table public.banners enable row level security;
alter table public.admin_device_tokens enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.notification_deliveries enable row level security;
alter table public.app_versions enable row level security;
alter table public.invite_tokens enable row level security;
alter table public.audit_logs enable row level security;
alter table public.sync_outbox enable row level security;
alter table public.edge_rate_limits enable row level security;

drop policy if exists "profiles self read" on public.profiles;
drop policy if exists "profiles admin manage" on public.profiles;
drop policy if exists "price groups readable" on public.price_groups;
drop policy if exists "price groups admin manage" on public.price_groups;
drop policy if exists "customers own or staff" on public.business_customers;
drop policy if exists "customers staff manage" on public.business_customers;
drop policy if exists "contacts own or staff" on public.customer_contacts;
drop policy if exists "contacts staff manage" on public.customer_contacts;
drop policy if exists "categories active readable" on public.categories;
drop policy if exists "categories staff manage" on public.categories;
drop policy if exists "products active readable" on public.products;
drop policy if exists "products staff manage" on public.products;
drop policy if exists "product images readable with products" on public.product_images;
drop policy if exists "product images staff manage" on public.product_images;
drop policy if exists "product prices readable" on public.product_prices;
drop policy if exists "product prices staff manage" on public.product_prices;
drop policy if exists "special prices scoped" on public.customer_special_prices;
drop policy if exists "special prices staff manage" on public.customer_special_prices;
drop policy if exists "inventory staff only" on public.inventory_movements;
drop policy if exists "orders own or staff read" on public.orders;
drop policy if exists "customers create own orders" on public.orders;
drop policy if exists "staff manage orders" on public.orders;
drop policy if exists "order items own or staff read" on public.order_items;
drop policy if exists "customers insert own order items" on public.order_items;
drop policy if exists "staff manage order items" on public.order_items;
drop policy if exists "order history own or staff read" on public.order_status_history;
drop policy if exists "inventory reservations staff read" on public.inventory_reservations;
drop policy if exists "settings readable" on public.app_settings;
drop policy if exists "settings admin manage" on public.app_settings;
drop policy if exists "banners readable" on public.banners;
drop policy if exists "banners staff manage" on public.banners;
drop policy if exists "device tokens owner or staff" on public.admin_device_tokens;
drop policy if exists "device tokens owner insert" on public.admin_device_tokens;
drop policy if exists "device tokens owner update" on public.admin_device_tokens;
drop policy if exists "device tokens owner read" on public.device_tokens;
drop policy if exists "device tokens owner insert" on public.device_tokens;
drop policy if exists "device tokens owner update" on public.device_tokens;
drop policy if exists "device tokens owner delete" on public.device_tokens;
drop policy if exists "notifications scoped read" on public.notifications;
drop policy if exists "notifications staff insert" on public.notifications;
drop policy if exists "notifications own mark read" on public.notifications;
drop policy if exists "notification outbox admin read" on public.notification_outbox;
drop policy if exists "notification deliveries admin read" on public.notification_deliveries;
drop policy if exists "app versions readable" on public.app_versions;
drop policy if exists "app versions admin manage" on public.app_versions;
drop policy if exists "invite tokens staff only" on public.invite_tokens;
drop policy if exists "invite tokens staff read" on public.invite_tokens;
drop policy if exists "audit logs admin read" on public.audit_logs;
drop policy if exists "audit logs staff insert" on public.audit_logs;
drop policy if exists "sync outbox own" on public.sync_outbox;

create policy "profiles self read"
on public.profiles
for select
using (id = auth.uid() or public.is_staff_or_admin());

create policy "profiles admin manage"
on public.profiles
for all
using (public.is_admin())
with check (public.is_admin());

create policy "price groups readable"
on public.price_groups
for select
using (
  public.is_active_actor()
  and (active or public.is_staff_or_admin())
);

create policy "price groups admin manage"
on public.price_groups
for all
using (public.is_admin())
with check (public.is_admin());

create policy "customers own or staff"
on public.business_customers
for select
using (profile_id = auth.uid() or public.is_staff_or_admin());

create policy "customers staff manage"
on public.business_customers
for all
using (public.is_staff_or_admin())
with check (public.is_staff_or_admin());

create policy "contacts own or staff"
on public.customer_contacts
for select
using (
  public.is_staff_or_admin()
  or exists (
    select 1
    from public.business_customers c
    where c.id = customer_id
      and c.profile_id = auth.uid()
  )
);

create policy "contacts staff manage"
on public.customer_contacts
for all
using (public.is_staff_or_admin())
with check (public.is_staff_or_admin());

create policy "categories active readable"
on public.categories
for select
using (
  public.is_active_actor()
  and (active or public.is_staff_or_admin())
);

create policy "categories staff manage"
on public.categories
for all
using (public.is_staff_or_admin())
with check (public.is_staff_or_admin());

create policy "products active readable"
on public.products
for select
using (
  public.is_active_actor()
  and ((active and archived_at is null) or public.is_staff_or_admin())
);

create policy "products staff manage"
on public.products
for all
using (public.is_staff_or_admin())
with check (public.is_staff_or_admin());

create policy "product images readable with products"
on public.product_images
for select
using (
  public.is_active_actor()
  and exists (
    select 1
    from public.products p
    where p.id = product_id
      and ((p.active and p.archived_at is null) or public.is_staff_or_admin())
  )
);

create policy "product images staff manage"
on public.product_images
for all
using (public.is_staff_or_admin())
with check (public.is_staff_or_admin());

create policy "product prices readable"
on public.product_prices
for select
using (
  public.is_staff_or_admin()
  or exists (
    select 1
    from public.business_customers c
    where c.id = public.current_customer_id()
      and c.price_group_id = product_prices.price_group_id
  )
);

create policy "product prices staff manage"
on public.product_prices
for all
using (public.is_staff_or_admin())
with check (public.is_staff_or_admin());

create policy "special prices scoped"
on public.customer_special_prices
for select
using (
  customer_id = public.current_customer_id()
  or public.is_staff_or_admin()
);

create policy "special prices staff manage"
on public.customer_special_prices
for all
using (public.is_staff_or_admin())
with check (public.is_staff_or_admin());

create policy "inventory staff only"
on public.inventory_movements
for all
using (public.is_staff_or_admin())
with check (
  public.is_staff_or_admin()
  and (created_by is null or created_by = auth.uid())
);

create policy "orders own or staff read"
on public.orders
for select
using (
  customer_id = public.current_customer_id()
  or public.is_staff_or_admin()
);

create policy "order items own or staff read"
on public.order_items
for select
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and (
        o.customer_id = public.current_customer_id()
        or public.is_staff_or_admin()
      )
  )
);

create policy "order history own or staff read"
on public.order_status_history
for select
using (
  public.is_staff_or_admin()
  or exists (
    select 1
    from public.orders o
    where o.id = order_id
      and o.customer_id = public.current_customer_id()
  )
);

create policy "inventory reservations staff read"
on public.inventory_reservations
for select
using (public.is_staff_or_admin());

create policy "settings readable"
on public.app_settings
for select
using (public.is_active_actor());

create policy "settings admin manage"
on public.app_settings
for all
using (public.is_admin())
with check (public.is_admin());

create policy "banners readable"
on public.banners
for select
using (
  public.is_active_actor()
  and (active or public.is_staff_or_admin())
);

create policy "banners staff manage"
on public.banners
for all
using (public.is_staff_or_admin())
with check (public.is_staff_or_admin());

create policy "admin device tokens owner read"
on public.admin_device_tokens
for select
using (profile_id = auth.uid() or public.is_admin());

create policy "admin device tokens owner insert"
on public.admin_device_tokens
for insert
with check (
  profile_id = auth.uid()
  and public.current_role() in ('admin','staff')
);

create policy "admin device tokens owner update"
on public.admin_device_tokens
for update
using (
  profile_id = auth.uid()
  and public.current_role() in ('admin','staff')
)
with check (
  profile_id = auth.uid()
  and public.current_role() in ('admin','staff')
);

create policy "device tokens owner read"
on public.device_tokens
for select
using (profile_id = auth.uid() or public.is_admin());

create policy "device tokens owner insert"
on public.device_tokens
for insert
with check (profile_id = auth.uid() and public.is_active_actor());

create policy "device tokens owner update"
on public.device_tokens
for update
using (profile_id = auth.uid() and public.is_active_actor())
with check (profile_id = auth.uid() and public.is_active_actor());

create policy "device tokens owner delete"
on public.device_tokens
for delete
using (profile_id = auth.uid());

create policy "notifications scoped read"
on public.notifications
for select
using (recipient_profile_id = auth.uid());

create policy "notifications own mark read"
on public.notifications
for update
using (recipient_profile_id = auth.uid())
with check (recipient_profile_id = auth.uid());

create policy "notification outbox admin read"
on public.notification_outbox
for select
using (public.is_admin());

create policy "notification deliveries admin read"
on public.notification_deliveries
for select
using (public.is_admin());

create policy "app versions readable"
on public.app_versions
for select
using (published or public.is_staff_or_admin());

create policy "app versions admin manage"
on public.app_versions
for all
using (public.is_admin())
with check (public.is_admin());

create policy "invite tokens staff read"
on public.invite_tokens
for select
using (public.is_staff_or_admin());

create policy "audit logs admin read"
on public.audit_logs
for select
using (public.is_admin());

create policy "sync outbox own"
on public.sync_outbox
for all
using (owner_id = auth.uid() or public.is_staff_or_admin())
with check (owner_id = auth.uid() or public.is_staff_or_admin());

revoke insert, update, delete on public.orders from anon, authenticated;
revoke insert, update, delete on public.order_items from anon, authenticated;
revoke insert, update, delete on public.order_status_history from anon, authenticated;
revoke insert, update, delete on public.inventory_reservations from anon, authenticated;
revoke insert, update, delete on public.notifications from anon, authenticated;
revoke insert, update, delete on public.notification_outbox from anon, authenticated;
revoke insert, update, delete on public.notification_deliveries from anon, authenticated;
revoke insert, update, delete on public.invite_tokens from anon, authenticated;
revoke insert, update, delete on public.audit_logs from anon, authenticated;
revoke all on public.edge_rate_limits from anon, authenticated;

grant select on public.orders, public.order_items, public.order_status_history
  to authenticated;
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
grant select, insert, update, delete on public.device_tokens to authenticated;
grant select, insert, update, delete on
  public.profiles,
  public.price_groups,
  public.business_customers,
  public.customer_contacts,
  public.categories,
  public.products,
  public.product_images,
  public.product_prices,
  public.customer_special_prices,
  public.inventory_movements,
  public.app_settings,
  public.banners,
  public.admin_device_tokens,
  public.app_versions,
  public.sync_outbox
to authenticated;
grant select on
  public.inventory_reservations,
  public.notification_outbox,
  public.notification_deliveries,
  public.invite_tokens,
  public.audit_logs
to authenticated;
grant select on public.app_versions to anon;

notify pgrst, 'reload schema';
