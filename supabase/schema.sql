create extension if not exists "pgcrypto";

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  full_name text,
  phone text,
  role text not null check (role in ('admin','staff','customer')),
  must_change_password boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists price_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists business_customers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references profiles(id) on delete set null,
  business_name text not null,
  contact_person text,
  phone text,
  city text,
  area text,
  address text,
  price_group_id uuid references price_groups(id),
  account_status text not null default 'active' check (account_status in ('active','suspended','archived')),
  credit_limit numeric(12,2) not null default 0,
  outstanding_balance numeric(12,2) not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists customer_contacts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references business_customers(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  role_title text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references categories(id),
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

create table if not exists product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  storage_path text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists product_prices (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  price_group_id uuid not null references price_groups(id) on delete cascade,
  price numeric(12,2) not null,
  unique(product_id, price_group_id)
);

create table if not exists customer_special_prices (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references business_customers(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  price numeric(12,2) not null,
  active boolean not null default true,
  unique(customer_id, product_id)
);

create table if not exists inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id),
  movement_type text not null check (movement_type in ('receive','adjust','reserve','sale','return')),
  quantity integer not null,
  note text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references business_customers(id),
  status text not null default 'pending' check (status in ('pending','confirmed','preparing','ready','delivered','cancelled')),
  subtotal numeric(12,2) not null default 0,
  delivery_note text,
  customer_note text,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null,
  line_total numeric(12,2) generated always as (quantity * unit_price) stored
);

create table if not exists app_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

create table if not exists banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  image_path text,
  image_url text,
  cta_text text,
  target_type text not null default 'catalog' check (target_type in ('catalog','category','product','url')),
  target_value text,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists admin_device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  fcm_token text not null unique,
  platform text not null default 'android',
  device_label text,
  active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid references profiles(id) on delete cascade,
  recipient_role text check (recipient_role in ('admin','staff','customer')),
  type text not null,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists app_versions (
  id uuid primary key default gen_random_uuid(),
  platform text not null default 'android',
  version_name text not null,
  version_code integer not null,
  apk_url text,
  required_update boolean not null default false,
  release_notes text,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(platform, version_code)
);

create table if not exists invite_tokens (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references business_customers(id) on delete cascade,
  token_hash text not null unique,
  client_code text,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references profiles(id),
  action text not null,
  entity_table text,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists sync_outbox (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references profiles(id),
  entity_type text not null,
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending','syncing','synced','failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_business_customers_profile on business_customers(profile_id);
create index if not exists idx_products_category on products(category_id);
create index if not exists idx_orders_customer on orders(customer_id);
create index if not exists idx_order_items_order on order_items(order_id);
create index if not exists idx_notifications_recipient on notifications(recipient_profile_id, created_at desc);
create index if not exists idx_notifications_role on notifications(recipient_role, created_at desc);
create index if not exists idx_admin_device_tokens_profile on admin_device_tokens(profile_id);
create index if not exists idx_app_versions_platform on app_versions(platform, published, version_code desc);

-- Storage note: create bucket product-images in Supabase dashboard or CLI.
