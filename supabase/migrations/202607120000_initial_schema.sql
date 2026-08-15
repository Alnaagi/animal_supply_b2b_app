-- Initial schema for new Supabase projects.
-- Every statement is idempotent so an existing project that was bootstrapped
-- with schema.sql can adopt the migration chain safely.

create extension if not exists "pgcrypto";
create sequence if not exists public.order_number_seq;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  full_name text,
  phone text,
  role text not null check (role in ('admin','staff','customer')),
  must_change_password boolean not null default false,
  active boolean not null default true,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.price_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_customers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  business_name text not null,
  contact_person text,
  phone text,
  city text,
  area text,
  address text,
  price_group_id uuid references public.price_groups(id),
  account_status text not null default 'active'
    check (account_status in ('active','suspended','archived')),
  credit_limit numeric(12,2) not null default 0,
  outstanding_balance numeric(12,2) not null default 0,
  ordering_block_reason text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_contacts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.business_customers(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  role_title text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.categories(id),
  name text not null,
  name_en text,
  sku text not null unique,
  barcode text,
  brand text,
  description text,
  animal_type text,
  unit_size text,
  package_size text,
  base_price numeric(12,2) not null default 0,
  old_price numeric(12,2),
  discount_percent integer,
  stock_quantity integer not null default 0,
  min_order_quantity integer not null default 1,
  image_url text,
  source_url text,
  tags text[] not null default '{}',
  active boolean not null default true,
  is_featured boolean not null default false,
  is_top_selling boolean not null default false,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  storage_path text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.product_prices (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  price_group_id uuid not null references public.price_groups(id) on delete cascade,
  price numeric(12,2) not null,
  unique(product_id, price_group_id)
);

create table if not exists public.customer_special_prices (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.business_customers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  price numeric(12,2) not null,
  active boolean not null default true,
  unique(customer_id, product_id)
);

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id),
  movement_type text not null
    check (movement_type in ('receive','adjust','reserve','sale','return')),
  quantity integer not null,
  note text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.business_customers(id),
  customer_profile_id uuid references public.profiles(id) on delete set null,
  order_number text not null unique,
  client_request_id uuid not null,
  business_name_snapshot text not null,
  contact_person_snapshot text not null default '',
  contact_phone_snapshot text not null default '',
  status text not null default 'pending'
    check (status in ('pending','confirmed','preparing','ready','delivered','cancelled')),
  subtotal numeric(12,2) not null default 0,
  delivery_fee numeric(12,2) not null default 0,
  handling_fee numeric(12,2) not null default 0,
  total numeric(12,2)
    generated always as (subtotal + delivery_fee + handling_fee) stored,
  delivery_address text not null default '',
  delivery_note text,
  customer_note text,
  admin_note text,
  placed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(customer_id, client_request_id),
  check (subtotal >= 0 and delivery_fee >= 0 and handling_fee >= 0)
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_name_snapshot text not null,
  product_sku_snapshot text not null,
  unit_size_snapshot text not null default '',
  package_label_snapshot text not null default '',
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  line_total numeric(12,2)
    generated always as (quantity * unit_price) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  from_status text
    check (
      from_status is null
      or from_status in ('pending','confirmed','preparing','ready','delivered','cancelled')
    ),
  to_status text not null
    check (to_status in ('pending','confirmed','preparing','ready','delivered','cancelled')),
  note text not null default '',
  changed_by uuid references public.profiles(id) on delete set null,
  changed_by_role text
    check (changed_by_role is null or changed_by_role in ('admin','staff','customer','system')),
  changed_at timestamptz not null default now()
);

create table if not exists public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  order_item_id uuid not null unique references public.order_items(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  status text not null default 'active'
    check (status in ('active','released','fulfilled')),
  released_at timestamptz,
  fulfilled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.inventory_movements
  add column if not exists order_id uuid references public.orders(id) on delete set null,
  add column if not exists order_item_id uuid references public.order_items(id) on delete set null;

create table if not exists public.app_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  image_path text,
  image_url text,
  cta_text text,
  target_type text not null default 'catalog'
    check (target_type in ('catalog','category','product','url')),
  target_value text,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  fcm_token text not null unique,
  platform text not null default 'android',
  device_label text,
  active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references public.profiles(id) on delete cascade,
  recipient_role text check (recipient_role in ('admin','staff','customer')),
  type text not null,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  dedupe_key text,
  expires_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android','ios','web')),
  device_id text,
  device_label text,
  app_version text,
  locale text not null default 'ar_LY',
  active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null unique
    references public.notifications(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','processing','sent','failed','dead')),
  attempts integer not null default 0 check (attempts >= 0),
  scheduled_at timestamptz not null default now(),
  next_attempt_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  sent_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null
    references public.notification_outbox(id) on delete cascade,
  device_token_id uuid references public.device_tokens(id) on delete set null,
  provider_message_id text,
  status text not null check (status in ('sent','failed','skipped')),
  error_code text,
  error_message text,
  attempted_at timestamptz not null default now()
);

create table if not exists public.app_versions (
  id uuid primary key default gen_random_uuid(),
  platform text not null default 'android',
  version_name text not null,
  version_code integer not null check (version_code > 0),
  minimum_supported_code integer not null default 1
    check (minimum_supported_code > 0 and minimum_supported_code <= version_code),
  apk_url text,
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-fA-F]{64}$'),
  file_size_bytes bigint check (file_size_bytes is null or file_size_bytes >= 0),
  required_update boolean not null default false,
  release_notes text,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(platform, version_code)
);

create table if not exists public.invite_tokens (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.business_customers(id) on delete cascade,
  token_hash text not null unique,
  client_code text,
  purpose text not null default 'activation'
    check (purpose in ('activation','password_reset')),
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  used_by uuid references public.profiles(id) on delete set null,
  created_by uuid references public.profiles(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_table text,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.sync_outbox (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.profiles(id),
  entity_type text not null,
  payload jsonb not null,
  status text not null default 'pending'
    check (status in ('pending','syncing','synced','failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.edge_rate_limits (
  endpoint text not null,
  key_hash text not null,
  window_started_at timestamptz not null default now(),
  attempts integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (endpoint, key_hash)
);

create index if not exists idx_business_customers_profile
  on public.business_customers(profile_id);
create index if not exists idx_products_category
  on public.products(category_id);
create index if not exists idx_orders_customer
  on public.orders(customer_id);
create index if not exists idx_orders_status_created
  on public.orders(status, created_at desc);
create index if not exists idx_order_items_order
  on public.order_items(order_id);
create index if not exists idx_order_status_history_order
  on public.order_status_history(order_id, changed_at);
create index if not exists idx_inventory_reservations_product_active
  on public.inventory_reservations(product_id)
  where status = 'active';
create index if not exists idx_inventory_reservations_order
  on public.inventory_reservations(order_id);
create index if not exists idx_notifications_recipient
  on public.notifications(recipient_profile_id, created_at desc);
create unique index if not exists idx_notifications_dedupe
  on public.notifications(dedupe_key)
  where dedupe_key is not null;
create index if not exists idx_admin_device_tokens_profile
  on public.admin_device_tokens(profile_id);
create index if not exists idx_device_tokens_profile_active
  on public.device_tokens(profile_id)
  where active;
create index if not exists idx_notification_outbox_pending
  on public.notification_outbox(next_attempt_at, created_at)
  where status in ('pending','failed');
create index if not exists idx_notification_deliveries_outbox
  on public.notification_deliveries(outbox_id, attempted_at desc);
create index if not exists idx_invite_tokens_active_customer
  on public.invite_tokens(customer_id, expires_at)
  where used_at is null and revoked_at is null;
create index if not exists idx_app_versions_platform
  on public.app_versions(platform, published, version_code desc);
