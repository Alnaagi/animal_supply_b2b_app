-- Production hardening for account access, ordering, invitations, and notifications.
-- This migration is intentionally additive so it can be applied after the legacy
-- schema.sql/rls.sql bootstrap without losing existing demo or production data.

create extension if not exists "pgcrypto";

create sequence if not exists public.order_number_seq;

alter table public.profiles
  add column if not exists last_login_at timestamptz;

alter table public.business_customers
  add column if not exists ordering_block_reason text;

alter table public.orders
  add column if not exists order_number text,
  add column if not exists client_request_id uuid,
  add column if not exists customer_profile_id uuid references public.profiles(id) on delete set null,
  add column if not exists business_name_snapshot text,
  add column if not exists contact_person_snapshot text,
  add column if not exists contact_phone_snapshot text,
  add column if not exists delivery_address text,
  add column if not exists delivery_fee numeric(12,2) not null default 0,
  add column if not exists handling_fee numeric(12,2) not null default 0,
  add column if not exists placed_by uuid references public.profiles(id) on delete set null;

update public.orders o
set
  order_number = coalesce(
    o.order_number,
    'AS-' || to_char(o.created_at at time zone 'Africa/Tripoli', 'YYYYMMDD')
      || '-' || lpad(nextval('public.order_number_seq')::text, 6, '0')
  ),
  client_request_id = coalesce(o.client_request_id, gen_random_uuid()),
  customer_profile_id = coalesce(o.customer_profile_id, c.profile_id),
  business_name_snapshot = coalesce(o.business_name_snapshot, c.business_name),
  contact_person_snapshot = coalesce(o.contact_person_snapshot, c.contact_person, ''),
  contact_phone_snapshot = coalesce(o.contact_phone_snapshot, c.phone, ''),
  delivery_address = coalesce(o.delivery_address, c.address, ''),
  placed_by = coalesce(o.placed_by, c.profile_id)
from public.business_customers c
where c.id = o.customer_id;

alter table public.orders
  alter column order_number set not null,
  alter column client_request_id set not null,
  alter column business_name_snapshot set not null,
  alter column contact_person_snapshot set default '',
  alter column contact_person_snapshot set not null,
  alter column contact_phone_snapshot set default '',
  alter column contact_phone_snapshot set not null,
  alter column delivery_address set default '',
  alter column delivery_address set not null;

alter table public.orders
  add column if not exists total numeric(12,2)
    generated always as (subtotal + delivery_fee + handling_fee) stored;

alter table public.order_items
  add column if not exists product_name_snapshot text,
  add column if not exists product_sku_snapshot text,
  add column if not exists unit_size_snapshot text,
  add column if not exists package_label_snapshot text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

update public.order_items oi
set
  product_name_snapshot = coalesce(oi.product_name_snapshot, p.name),
  product_sku_snapshot = coalesce(oi.product_sku_snapshot, p.sku),
  unit_size_snapshot = coalesce(oi.unit_size_snapshot, p.unit_size, ''),
  package_label_snapshot = coalesce(
    oi.package_label_snapshot,
    nullif(p.package_size, ''),
    nullif(p.unit_size, ''),
    ''
  )
from public.products p
where p.id = oi.product_id;

alter table public.order_items
  alter column product_name_snapshot set not null,
  alter column product_sku_snapshot set not null,
  alter column unit_size_snapshot set default '',
  alter column unit_size_snapshot set not null,
  alter column package_label_snapshot set default '',
  alter column package_label_snapshot set not null;

alter table public.inventory_movements
  add column if not exists order_id uuid references public.orders(id) on delete set null,
  add column if not exists order_item_id uuid references public.order_items(id) on delete set null;

alter table public.invite_tokens
  add column if not exists purpose text not null default 'activation',
  add column if not exists revoked_at timestamptz,
  add column if not exists used_by uuid references public.profiles(id) on delete set null,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.notifications
  add column if not exists dedupe_key text,
  add column if not exists expires_at timestamptz;

alter table public.app_versions
  add column if not exists minimum_supported_code integer not null default 1,
  add column if not exists sha256 text,
  add column if not exists file_size_bytes bigint;

-- Convert legacy role broadcasts to one row per active recipient. A shared
-- read_at on a role broadcast would otherwise mark the message read for every
-- user in that role.
insert into public.notifications (
  recipient_profile_id,
  recipient_role,
  type,
  title,
  body,
  payload,
  read_at,
  created_at,
  expires_at,
  dedupe_key
)
select
  p.id,
  p.role,
  n.type,
  n.title,
  n.body,
  n.payload,
  n.read_at,
  n.created_at,
  n.expires_at,
  'legacy-broadcast:' || n.id::text || ':' || p.id::text
from public.notifications n
join public.profiles p
  on p.role = n.recipient_role
 and p.active
where n.recipient_profile_id is null
  and n.recipient_role is not null;

delete from public.notifications
where recipient_profile_id is null;

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  from_status text,
  to_status text not null,
  note text not null default '',
  changed_by uuid references public.profiles(id) on delete set null,
  changed_by_role text,
  changed_at timestamptz not null default now()
);

create table if not exists public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  order_item_id uuid not null unique references public.order_items(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity integer not null,
  status text not null default 'active',
  released_at timestamptz,
  fulfilled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null,
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
  notification_id uuid not null unique references public.notifications(id) on delete cascade,
  status text not null default 'pending',
  attempts integer not null default 0,
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
  outbox_id uuid not null references public.notification_outbox(id) on delete cascade,
  device_token_id uuid references public.device_tokens(id) on delete set null,
  provider_message_id text,
  status text not null,
  error_code text,
  error_message text,
  attempted_at timestamptz not null default now()
);

create table if not exists public.edge_rate_limits (
  endpoint text not null,
  key_hash text not null,
  window_started_at timestamptz not null default now(),
  attempts integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (endpoint, key_hash)
);

insert into public.device_tokens (
  profile_id,
  token,
  platform,
  device_label,
  active,
  last_seen_at,
  created_at,
  updated_at
)
select
  profile_id,
  fcm_token,
  case
    when platform in ('android', 'ios', 'web') then platform
    else 'android'
  end,
  device_label,
  active,
  last_seen_at,
  created_at,
  updated_at
from public.admin_device_tokens
on conflict (token) do update set
  profile_id = excluded.profile_id,
  platform = excluded.platform,
  device_label = excluded.device_label,
  active = excluded.active,
  last_seen_at = excluded.last_seen_at,
  updated_at = excluded.updated_at;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'business_customers_credit_limit_nonnegative'
      and conrelid = 'public.business_customers'::regclass
  ) then
    alter table public.business_customers
      add constraint business_customers_credit_limit_nonnegative
      check (credit_limit >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'business_customers_outstanding_nonnegative'
      and conrelid = 'public.business_customers'::regclass
  ) then
    alter table public.business_customers
      add constraint business_customers_outstanding_nonnegative
      check (outstanding_balance >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'products_price_nonnegative'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_price_nonnegative
      check (base_price >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'products_stock_nonnegative'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_stock_nonnegative
      check (stock_quantity >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'products_moq_positive'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_moq_positive
      check (min_order_quantity > 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'product_prices_price_nonnegative'
      and conrelid = 'public.product_prices'::regclass
  ) then
    alter table public.product_prices
      add constraint product_prices_price_nonnegative
      check (price >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'customer_special_prices_price_nonnegative'
      and conrelid = 'public.customer_special_prices'::regclass
  ) then
    alter table public.customer_special_prices
      add constraint customer_special_prices_price_nonnegative
      check (price >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_amounts_nonnegative'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders
      add constraint orders_amounts_nonnegative
      check (subtotal >= 0 and delivery_fee >= 0 and handling_fee >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'order_items_unit_price_nonnegative'
      and conrelid = 'public.order_items'::regclass
  ) then
    alter table public.order_items
      add constraint order_items_unit_price_nonnegative
      check (unit_price >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'order_status_history_from_status_check'
      and conrelid = 'public.order_status_history'::regclass
  ) then
    alter table public.order_status_history
      add constraint order_status_history_from_status_check
      check (
        from_status is null
        or from_status in ('pending','confirmed','preparing','ready','delivered','cancelled')
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'order_status_history_to_status_check'
      and conrelid = 'public.order_status_history'::regclass
  ) then
    alter table public.order_status_history
      add constraint order_status_history_to_status_check
      check (to_status in ('pending','confirmed','preparing','ready','delivered','cancelled'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'order_status_history_role_check'
      and conrelid = 'public.order_status_history'::regclass
  ) then
    alter table public.order_status_history
      add constraint order_status_history_role_check
      check (changed_by_role is null or changed_by_role in ('admin','staff','customer','system'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'inventory_reservations_quantity_positive'
      and conrelid = 'public.inventory_reservations'::regclass
  ) then
    alter table public.inventory_reservations
      add constraint inventory_reservations_quantity_positive check (quantity > 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'inventory_reservations_status_check'
      and conrelid = 'public.inventory_reservations'::regclass
  ) then
    alter table public.inventory_reservations
      add constraint inventory_reservations_status_check
      check (status in ('active','released','fulfilled'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'device_tokens_platform_check'
      and conrelid = 'public.device_tokens'::regclass
  ) then
    alter table public.device_tokens
      add constraint device_tokens_platform_check check (platform in ('android','ios','web'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'notification_outbox_status_check'
      and conrelid = 'public.notification_outbox'::regclass
  ) then
    alter table public.notification_outbox
      add constraint notification_outbox_status_check
      check (status in ('pending','processing','sent','failed','dead'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'notification_outbox_attempts_nonnegative'
      and conrelid = 'public.notification_outbox'::regclass
  ) then
    alter table public.notification_outbox
      add constraint notification_outbox_attempts_nonnegative check (attempts >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'notification_deliveries_status_check'
      and conrelid = 'public.notification_deliveries'::regclass
  ) then
    alter table public.notification_deliveries
      add constraint notification_deliveries_status_check
      check (status in ('sent','failed','skipped'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'notifications_profile_recipient_required'
      and conrelid = 'public.notifications'::regclass
  ) then
    alter table public.notifications
      add constraint notifications_profile_recipient_required
      check (recipient_profile_id is not null);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'invite_tokens_purpose_check'
      and conrelid = 'public.invite_tokens'::regclass
  ) then
    alter table public.invite_tokens
      add constraint invite_tokens_purpose_check
      check (purpose in ('activation','password_reset'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'app_versions_minimum_code_positive'
      and conrelid = 'public.app_versions'::regclass
  ) then
    alter table public.app_versions
      add constraint app_versions_minimum_code_positive
      check (
        minimum_supported_code > 0
        and version_code > 0
        and minimum_supported_code <= version_code
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'app_versions_file_size_nonnegative'
      and conrelid = 'public.app_versions'::regclass
  ) then
    alter table public.app_versions
      add constraint app_versions_file_size_nonnegative
      check (file_size_bytes is null or file_size_bytes >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'app_versions_sha256_format'
      and conrelid = 'public.app_versions'::regclass
  ) then
    alter table public.app_versions
      add constraint app_versions_sha256_format
      check (sha256 is null or sha256 ~ '^[0-9a-fA-F]{64}$') not valid;
  end if;
end
$$;

create unique index if not exists idx_orders_order_number
  on public.orders(order_number);
create unique index if not exists idx_orders_customer_request
  on public.orders(customer_id, client_request_id);
create index if not exists idx_orders_status_created
  on public.orders(status, created_at desc);
create index if not exists idx_order_status_history_order
  on public.order_status_history(order_id, changed_at);
create index if not exists idx_inventory_reservations_product_active
  on public.inventory_reservations(product_id)
  where status = 'active';
create index if not exists idx_inventory_reservations_order
  on public.inventory_reservations(order_id);
create index if not exists idx_device_tokens_profile_active
  on public.device_tokens(profile_id)
  where active;
create unique index if not exists idx_notifications_dedupe
  on public.notifications(dedupe_key)
  where dedupe_key is not null;
create index if not exists idx_notification_outbox_pending
  on public.notification_outbox(next_attempt_at, created_at)
  where status in ('pending','failed');
create index if not exists idx_notification_deliveries_outbox
  on public.notification_deliveries(outbox_id, attempted_at desc);
create index if not exists idx_invite_tokens_active_customer
  on public.invite_tokens(customer_id, expires_at)
  where used_at is null and revoked_at is null;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles',
    'price_groups',
    'business_customers',
    'customer_contacts',
    'categories',
    'products',
    'orders',
    'order_items',
    'banners',
    'app_settings',
    'app_versions',
    'device_tokens',
    'notification_outbox',
    'inventory_reservations'
  ]
  loop
    execute format('drop trigger if exists set_updated_at on public.%I', table_name);
    execute format(
      'create trigger set_updated_at before update on public.%I '
      || 'for each row execute function public.touch_updated_at()',
      table_name
    );
  end loop;
end
$$;

create or replace function public.current_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
    and p.active
$$;

create or replace function public.is_active_actor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.active
  )
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_role() = 'admin', false)
$$;

create or replace function public.is_staff_or_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_role() in ('admin','staff'), false)
$$;

create or replace function public.current_customer_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select c.id
  from public.business_customers c
  join public.profiles p on p.id = c.profile_id
  where c.profile_id = auth.uid()
    and p.active
    and p.role = 'customer'
    and c.account_status = 'active'
$$;

create or replace function public.is_active_customer()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_customer_id() is not null
$$;

create or replace function public.app_setting_numeric(
  p_key text,
  p_default numeric default 0
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case
        when trim(s.value) ~ '^[0-9]+([.][0-9]+)?$' then trim(s.value)::numeric
        else p_default
      end
      from public.app_settings s
      where s.key = p_key
    ),
    p_default
  )
$$;

create or replace function public.effective_product_price(
  p_customer_id uuid,
  p_product_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select sp.price
      from public.customer_special_prices sp
      where sp.customer_id = p_customer_id
        and sp.product_id = p_product_id
        and sp.active
      limit 1
    ),
    (
      select pp.price
      from public.business_customers c
      join public.product_prices pp on pp.price_group_id = c.price_group_id
      where c.id = p_customer_id
        and pp.product_id = p_product_id
      limit 1
    ),
    (
      select p.base_price
      from public.products p
      where p.id = p_product_id
    )
  )
$$;

create or replace function public.enqueue_notification(
  p_recipient_profile_id uuid,
  p_recipient_role text,
  p_type text,
  p_title text,
  p_body text,
  p_payload jsonb,
  p_dedupe_key text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_notification_id uuid;
begin
  insert into public.notifications (
    recipient_profile_id,
    recipient_role,
    type,
    title,
    body,
    payload,
    dedupe_key
  )
  values (
    p_recipient_profile_id,
    p_recipient_role,
    p_type,
    p_title,
    p_body,
    coalesce(p_payload, '{}'::jsonb),
    p_dedupe_key
  )
  on conflict do nothing
  returning id into v_notification_id;

  if v_notification_id is null and p_dedupe_key is not null then
    select n.id
    into v_notification_id
    from public.notifications n
    where n.dedupe_key = p_dedupe_key;
  end if;

  if v_notification_id is not null then
    insert into public.notification_outbox (notification_id)
    values (v_notification_id)
    on conflict (notification_id) do nothing;
  end if;

  return v_notification_id;
end;
$$;

create or replace function public.order_payload(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', o.id,
    'order_number', o.order_number,
    'client_request_id', o.client_request_id,
    'customer_id', o.customer_id,
    'customer_profile_id', o.customer_profile_id,
    'customer_name', o.contact_person_snapshot,
    'business_name', o.business_name_snapshot,
    'contact_person', o.contact_person_snapshot,
    'contact_phone', o.contact_phone_snapshot,
    'status', o.status,
    'subtotal', o.subtotal,
    'delivery_fee', o.delivery_fee,
    'handling_fee', o.handling_fee,
    'total', o.total,
    'delivery_address', o.delivery_address,
    'delivery_note', coalesce(o.delivery_note, ''),
    'customer_note', coalesce(o.customer_note, ''),
    'notes', coalesce(o.customer_note, ''),
    'admin_note', coalesce(o.admin_note, ''),
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    'items', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', oi.id,
            'product_id', oi.product_id,
            'product_name', oi.product_name_snapshot,
            'product_sku', oi.product_sku_snapshot,
            'sku', oi.product_sku_snapshot,
            'unit_size', oi.unit_size_snapshot,
            'package_label', oi.package_label_snapshot,
            'quantity', oi.quantity,
            'unit_price', oi.unit_price,
            'line_total', oi.line_total
          )
          order by oi.created_at, oi.id
        )
        from public.order_items oi
        where oi.order_id = o.id
      ),
      '[]'::jsonb
    )
  )
  from public.orders o
  where o.id = p_order_id
$$;

create or replace function public.order_status_history_payload(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', h.id,
        'from_status', h.from_status,
        'to_status', h.to_status,
        'note', h.note,
        'changed_by', h.changed_by,
        'changed_by_role', h.changed_by_role,
        'changed_at', h.changed_at
      )
      order by h.changed_at, h.id
    ),
    '[]'::jsonb
  )
  from public.order_status_history h
  where h.order_id = p_order_id
$$;

create or replace function public.place_order_transaction(
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
declare
  actor_role text;
  customer public.business_customers%rowtype;
  existing_order_id uuid;
  new_order_id uuid;
  new_order_number text;
  item record;
  product public.products%rowtype;
  order_item_id uuid;
  effective_price numeric(12,2);
  reserved_quantity integer;
  subtotal_amount numeric(12,2) := 0;
  minimum_order_amount numeric(12,2);
  configured_delivery_fee numeric(12,2);
  configured_handling_fee numeric(12,2);
  resolved_delivery_address text;
  recipient record;
begin
  if p_actor_id is null then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;

  if p_client_request_id is null then
    raise exception using errcode = 'P0001', message = 'CLIENT_REQUEST_ID_REQUIRED';
  end if;

  if p_items is null
    or jsonb_typeof(p_items) <> 'array'
    or jsonb_array_length(p_items) = 0
  then
    raise exception using errcode = 'P0001', message = 'ORDER_ITEMS_REQUIRED';
  end if;

  if jsonb_array_length(p_items) > 100 then
    raise exception using errcode = 'P0001', message = 'TOO_MANY_ORDER_ITEMS';
  end if;

  select c.*
  into customer
  from public.business_customers c
  join public.profiles p on p.id = c.profile_id
  where p.id = p_actor_id
    and p.active
    and not p.must_change_password
    and p.role = 'customer'
  for update of c;

  if not found then
    raise exception using errcode = 'P0001', message = 'CUSTOMER_ACCOUNT_NOT_FOUND';
  end if;

  actor_role := 'customer';

  if customer.account_status <> 'active' then
    raise exception using
      errcode = 'P0001',
      message = 'CUSTOMER_ACCOUNT_INACTIVE',
      detail = coalesce(customer.ordering_block_reason, customer.account_status);
  end if;

  select o.id
  into existing_order_id
  from public.orders o
  where o.customer_id = customer.id
    and o.client_request_id = p_client_request_id;

  if existing_order_id is not null then
    return jsonb_build_object(
      'order', public.order_payload(existing_order_id),
      'idempotent', true
    );
  end if;

  if length(coalesce(p_customer_note, '')) > 1000
    or length(coalesce(p_delivery_note, '')) > 1000
    or length(coalesce(p_delivery_address, '')) > 500
  then
    raise exception using errcode = 'P0001', message = 'ORDER_TEXT_TOO_LONG';
  end if;

  minimum_order_amount := greatest(public.app_setting_numeric('minimum_order_amount', 0), 0);
  configured_delivery_fee := greatest(public.app_setting_numeric('delivery_fee', 0), 0);
  configured_handling_fee := greatest(public.app_setting_numeric('handling_fee', 0), 0);
  resolved_delivery_address := coalesce(
    nullif(trim(p_delivery_address), ''),
    nullif(trim(customer.address), ''),
    ''
  );
  new_order_number := 'AS-'
    || to_char(now() at time zone 'Africa/Tripoli', 'YYYYMMDD')
    || '-'
    || lpad(nextval('public.order_number_seq')::text, 6, '0');

  insert into public.orders (
    order_number,
    client_request_id,
    customer_id,
    customer_profile_id,
    business_name_snapshot,
    contact_person_snapshot,
    contact_phone_snapshot,
    status,
    subtotal,
    delivery_fee,
    handling_fee,
    delivery_address,
    delivery_note,
    customer_note,
    placed_by
  )
  values (
    new_order_number,
    p_client_request_id,
    customer.id,
    customer.profile_id,
    customer.business_name,
    coalesce(customer.contact_person, ''),
    coalesce(customer.phone, ''),
    'pending',
    0,
    configured_delivery_fee,
    configured_handling_fee,
    resolved_delivery_address,
    nullif(trim(p_delivery_note), ''),
    nullif(trim(p_customer_note), ''),
    p_actor_id
  )
  returning id into new_order_id;

  for item in
    select parsed.product_id, sum(parsed.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as parsed(product_id uuid, quantity integer)
    group by parsed.product_id
    order by parsed.product_id
  loop
    if item.product_id is null or item.quantity is null or item.quantity <= 0 then
      raise exception using errcode = 'P0001', message = 'INVALID_ORDER_ITEM';
    end if;

    select p.*
    into product
    from public.products p
    where p.id = item.product_id
    for update;

    if not found or not product.active or product.archived_at is not null then
      raise exception using
        errcode = 'P0001',
        message = 'PRODUCT_UNAVAILABLE',
        detail = item.product_id::text;
    end if;

    if item.quantity < product.min_order_quantity then
      raise exception using
        errcode = 'P0001',
        message = 'MINIMUM_QUANTITY_NOT_MET',
        detail = jsonb_build_object(
          'product_id', product.id,
          'minimum_quantity', product.min_order_quantity,
          'requested_quantity', item.quantity
        )::text;
    end if;

    select coalesce(sum(r.quantity), 0)::integer
    into reserved_quantity
    from public.inventory_reservations r
    where r.product_id = product.id
      and r.status = 'active';

    if product.stock_quantity - reserved_quantity < item.quantity then
      raise exception using
        errcode = 'P0001',
        message = 'INSUFFICIENT_STOCK',
        detail = jsonb_build_object(
          'product_id', product.id,
          'available_quantity', greatest(product.stock_quantity - reserved_quantity, 0),
          'requested_quantity', item.quantity
        )::text;
    end if;

    effective_price := public.effective_product_price(customer.id, product.id);
    if effective_price is null or effective_price < 0 then
      raise exception using
        errcode = 'P0001',
        message = 'PRODUCT_PRICE_UNAVAILABLE',
        detail = product.id::text;
    end if;

    insert into public.order_items (
      order_id,
      product_id,
      product_name_snapshot,
      product_sku_snapshot,
      unit_size_snapshot,
      package_label_snapshot,
      quantity,
      unit_price
    )
    values (
      new_order_id,
      product.id,
      product.name,
      product.sku,
      coalesce(product.unit_size, ''),
      coalesce(nullif(product.package_size, ''), nullif(product.unit_size, ''), ''),
      item.quantity,
      effective_price
    )
    returning id into order_item_id;

    insert into public.inventory_reservations (
      order_id,
      order_item_id,
      product_id,
      quantity
    )
    values (
      new_order_id,
      order_item_id,
      product.id,
      item.quantity
    );

    subtotal_amount := subtotal_amount + (effective_price * item.quantity);
  end loop;

  if subtotal_amount < minimum_order_amount then
    raise exception using
      errcode = 'P0001',
      message = 'MINIMUM_ORDER_AMOUNT_NOT_MET',
      detail = jsonb_build_object(
        'minimum_order_amount', minimum_order_amount,
        'subtotal', subtotal_amount
      )::text;
  end if;

  update public.orders
  set subtotal = subtotal_amount
  where id = new_order_id;

  insert into public.order_status_history (
    order_id,
    from_status,
    to_status,
    note,
    changed_by,
    changed_by_role
  )
  values (
    new_order_id,
    null,
    'pending',
    'تم إرسال الطلب من العميل',
    p_actor_id,
    actor_role
  );

  for recipient in
    select p.id, p.role
    from public.profiles p
    where p.active
      and p.role in ('admin', 'staff')
  loop
    perform public.enqueue_notification(
      recipient.id,
      recipient.role,
      'new_order',
      'طلب جديد',
      customer.business_name || ' أرسل الطلب ' || new_order_number
        || ' بقيمة ' || to_char(
          subtotal_amount + configured_delivery_fee + configured_handling_fee,
          'FM999999990.00'
        ) || ' د.ل',
      jsonb_build_object(
        'order_id', new_order_id,
        'order_number', new_order_number,
        'status', 'pending',
        'type', 'new_order'
      ),
      'order:new:' || new_order_id::text || ':' || recipient.id::text
    );
  end loop;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    p_actor_id,
    'order.created',
    'orders',
    new_order_id,
    jsonb_build_object(
      'order_number', new_order_number,
      'client_request_id', p_client_request_id,
      'subtotal', subtotal_amount,
      'total', subtotal_amount + configured_delivery_fee + configured_handling_fee
    )
  );

  return jsonb_build_object(
    'order', public.order_payload(new_order_id),
    'idempotent', false
  );
end;
$$;

create or replace function public.transition_order_status_transaction(
  p_actor_id uuid,
  p_order_id uuid,
  p_status text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  current_order public.orders%rowtype;
  reservation record;
  status_label text;
begin
  select p.role
  into actor_role
  from public.profiles p
  where p.id = p_actor_id
    and p.active
    and not p.must_change_password
    and p.role in ('admin', 'staff');

  if actor_role is null then
    raise exception using errcode = 'P0001', message = 'STAFF_AUTH_REQUIRED';
  end if;

  if p_status not in ('pending','confirmed','preparing','ready','delivered','cancelled') then
    raise exception using errcode = 'P0001', message = 'INVALID_ORDER_STATUS';
  end if;

  if length(coalesce(p_note, '')) > 1000 then
    raise exception using errcode = 'P0001', message = 'ORDER_NOTE_TOO_LONG';
  end if;

  select o.*
  into current_order
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'ORDER_NOT_FOUND';
  end if;

  if current_order.status = p_status then
    return jsonb_build_object(
      'order', public.order_payload(current_order.id)
        || jsonb_build_object(
          'status_history',
          public.order_status_history_payload(current_order.id)
        ),
      'idempotent', true
    );
  end if;

  if not (
    (current_order.status = 'pending' and p_status in ('confirmed','cancelled'))
    or (current_order.status = 'confirmed' and p_status in ('preparing','cancelled'))
    or (current_order.status = 'preparing' and p_status in ('ready','cancelled'))
    or (current_order.status = 'ready' and p_status in ('delivered','cancelled'))
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'INVALID_STATUS_TRANSITION',
      detail = current_order.status || ' -> ' || p_status;
  end if;

  if p_status = 'delivered' then
    for reservation in
      select r.id, r.product_id, r.quantity, r.order_item_id
      from public.inventory_reservations r
      where r.order_id = current_order.id
        and r.status = 'active'
      order by r.product_id
    loop
      perform 1
      from public.products p
      where p.id = reservation.product_id
      for update;

      if (
        select p.stock_quantity
        from public.products p
        where p.id = reservation.product_id
      ) < reservation.quantity then
        raise exception using
          errcode = 'P0001',
          message = 'INSUFFICIENT_STOCK_AT_DELIVERY',
          detail = reservation.product_id::text;
      end if;

      update public.products
      set stock_quantity = stock_quantity - reservation.quantity
      where id = reservation.product_id;

      update public.inventory_reservations
      set
        status = 'fulfilled',
        fulfilled_at = now()
      where id = reservation.id;

      insert into public.inventory_movements (
        product_id,
        movement_type,
        quantity,
        note,
        created_by,
        order_id,
        order_item_id
      )
      values (
        reservation.product_id,
        'sale',
        -reservation.quantity,
        'خصم مخزون عند تسليم الطلب ' || current_order.order_number,
        p_actor_id,
        current_order.id,
        reservation.order_item_id
      );
    end loop;
  elsif p_status = 'cancelled' then
    update public.inventory_reservations
    set
      status = 'released',
      released_at = now()
    where order_id = current_order.id
      and status = 'active';
  end if;

  update public.orders
  set
    status = p_status,
    admin_note = case
      when nullif(trim(p_note), '') is not null then trim(p_note)
      else admin_note
    end
  where id = current_order.id;

  insert into public.order_status_history (
    order_id,
    from_status,
    to_status,
    note,
    changed_by,
    changed_by_role
  )
  values (
    current_order.id,
    current_order.status,
    p_status,
    coalesce(trim(p_note), ''),
    p_actor_id,
    actor_role
  );

  status_label := case p_status
    when 'confirmed' then 'تم تأكيد طلبك'
    when 'preparing' then 'طلبك قيد التجهيز'
    when 'ready' then 'طلبك جاهز'
    when 'delivered' then 'تم تسليم طلبك'
    when 'cancelled' then 'تم إلغاء طلبك'
    else 'تم تحديث طلبك'
  end;

  if current_order.customer_profile_id is not null then
    perform public.enqueue_notification(
      current_order.customer_profile_id,
      'customer',
      'order_status_changed',
      status_label,
      'حالة الطلب ' || current_order.order_number || ' أصبحت: ' || status_label,
      jsonb_build_object(
        'order_id', current_order.id,
        'order_number', current_order.order_number,
        'status', p_status,
        'previous_status', current_order.status,
        'type', 'order_status_changed'
      ),
      'order:status:' || current_order.id::text || ':' || p_status
    );
  end if;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    p_actor_id,
    'order.status_changed',
    'orders',
    current_order.id,
    jsonb_build_object(
      'from_status', current_order.status,
      'to_status', p_status,
      'note', coalesce(trim(p_note), '')
    )
  );

  return jsonb_build_object(
    'order', public.order_payload(current_order.id)
      || jsonb_build_object(
        'status_history',
        public.order_status_history_payload(current_order.id)
      ),
    'idempotent', false
  );
end;
$$;

create or replace function public.redeem_invite_token(
  p_token_hash text,
  p_client_code text default null,
  p_redeemed_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  invite public.invite_tokens%rowtype;
  customer public.business_customers%rowtype;
  profile public.profiles%rowtype;
begin
  if p_token_hash is null or length(p_token_hash) <> 64 then
    raise exception using errcode = 'P0001', message = 'INVALID_INVITE_TOKEN';
  end if;

  select i.*
  into invite
  from public.invite_tokens i
  where i.token_hash = lower(p_token_hash)
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVALID_INVITE_TOKEN';
  end if;

  if invite.revoked_at is not null then
    raise exception using errcode = 'P0001', message = 'INVITE_REVOKED';
  end if;

  if invite.used_at is not null then
    raise exception using errcode = 'P0001', message = 'INVITE_ALREADY_USED';
  end if;

  if invite.expires_at <= now() then
    raise exception using errcode = 'P0001', message = 'INVITE_EXPIRED';
  end if;

  select c.*
  into customer
  from public.business_customers c
  where c.id = invite.customer_id;

  if not found or customer.profile_id is null then
    raise exception using errcode = 'P0001', message = 'INVITE_CUSTOMER_NOT_FOUND';
  end if;

  select p.*
  into profile
  from public.profiles p
  where p.id = customer.profile_id
    and p.role = 'customer';

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITE_CUSTOMER_NOT_FOUND';
  end if;

  if not profile.active or customer.account_status <> 'active' then
    raise exception using errcode = 'P0001', message = 'CUSTOMER_ACCOUNT_INACTIVE';
  end if;

  if nullif(trim(p_client_code), '') is not null
    and lower(trim(p_client_code)) <> lower(coalesce(invite.client_code, profile.username, ''))
  then
    raise exception using errcode = 'P0001', message = 'INVITE_CLIENT_CODE_MISMATCH';
  end if;

  if p_redeemed_by is not null and p_redeemed_by <> profile.id then
    raise exception using errcode = 'P0001', message = 'INVITE_USER_MISMATCH';
  end if;

  update public.invite_tokens
  set
    used_at = now(),
    used_by = p_redeemed_by
  where id = invite.id;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    p_redeemed_by,
    'invite.redeemed',
    'business_customers',
    customer.id,
    jsonb_build_object(
      'invite_id', invite.id,
      'purpose', invite.purpose
    )
  );

  return jsonb_build_object(
    'purpose', invite.purpose,
    'client_code', coalesce(invite.client_code, profile.username),
    'business_name', customer.business_name,
    'must_change_password', profile.must_change_password,
    'expires_at', invite.expires_at
  );
end;
$$;

create or replace function public.consume_edge_rate_limit(
  p_endpoint text,
  p_key_hash text,
  p_limit integer,
  p_window_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rate_row public.edge_rate_limits%rowtype;
  reset_at timestamptz;
begin
  if p_limit < 1 or p_window_seconds < 1 then
    raise exception using errcode = 'P0001', message = 'INVALID_RATE_LIMIT_CONFIG';
  end if;

  insert into public.edge_rate_limits (
    endpoint,
    key_hash,
    window_started_at,
    attempts
  )
  values (
    p_endpoint,
    p_key_hash,
    now(),
    0
  )
  on conflict (endpoint, key_hash) do nothing;

  select r.*
  into rate_row
  from public.edge_rate_limits r
  where r.endpoint = p_endpoint
    and r.key_hash = p_key_hash
  for update;

  if rate_row.window_started_at + make_interval(secs => p_window_seconds) <= now() then
    update public.edge_rate_limits
    set
      window_started_at = now(),
      attempts = 1
    where endpoint = p_endpoint
      and key_hash = p_key_hash
    returning * into rate_row;
  else
    update public.edge_rate_limits
    set attempts = attempts + 1
    where endpoint = p_endpoint
      and key_hash = p_key_hash
    returning * into rate_row;
  end if;

  reset_at := rate_row.window_started_at + make_interval(secs => p_window_seconds);

  return jsonb_build_object(
    'allowed', rate_row.attempts <= p_limit,
    'remaining', greatest(p_limit - rate_row.attempts, 0),
    'reset_at', reset_at
  );
end;
$$;

create or replace function public.send_notification_campaign_transaction(
  p_actor_id uuid,
  p_campaign_id uuid,
  p_title text,
  p_body text,
  p_type text,
  p_payload jsonb,
  p_audience jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  audience_type text;
  audience_role text;
  recipient record;
  recipient_count integer := 0;
begin
  select p.role
  into actor_role
  from public.profiles p
  where p.id = p_actor_id
    and p.active
    and p.role = 'admin';

  if actor_role is null then
    raise exception using errcode = 'P0001', message = 'ADMIN_AUTH_REQUIRED';
  end if;

  if p_campaign_id is null then
    raise exception using errcode = 'P0001', message = 'CAMPAIGN_ID_REQUIRED';
  end if;

  if nullif(trim(p_title), '') is null
    or length(trim(p_title)) > 160
    or nullif(trim(p_body), '') is null
    or length(trim(p_body)) > 1000
  then
    raise exception using errcode = 'P0001', message = 'INVALID_CAMPAIGN_CONTENT';
  end if;

  if p_type is null or p_type !~ '^[a-z][a-z0-9_.-]{1,63}$' then
    raise exception using errcode = 'P0001', message = 'INVALID_NOTIFICATION_TYPE';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = 'P0001', message = 'INVALID_NOTIFICATION_PAYLOAD';
  end if;

  if p_audience is null or jsonb_typeof(p_audience) <> 'object' then
    raise exception using errcode = 'P0001', message = 'INVALID_CAMPAIGN_AUDIENCE';
  end if;

  audience_type := p_audience->>'type';
  if audience_type is null
    or audience_type not in ('all','role','profile_ids','customer_ids','city')
  then
    raise exception using errcode = 'P0001', message = 'INVALID_CAMPAIGN_AUDIENCE';
  end if;

  audience_role := p_audience->>'role';
  if audience_type = 'role'
    and (
      audience_role is null
      or audience_role not in ('admin','staff','customer')
    )
  then
    raise exception using errcode = 'P0001', message = 'INVALID_CAMPAIGN_ROLE';
  end if;

  for recipient in
    select distinct p.id, p.role
    from public.profiles p
    left join public.business_customers c on c.profile_id = p.id
    where p.active
      and (
        p.role <> 'customer'
        or c.account_status = 'active'
      )
      and (
        audience_type = 'all'
        or (
          audience_type = 'role'
          and p.role = audience_role
        )
        or (
          audience_type = 'profile_ids'
          and jsonb_typeof(p_audience->'profile_ids') = 'array'
          and p.id in (
            select value::uuid
            from jsonb_array_elements_text(p_audience->'profile_ids')
          )
        )
        or (
          audience_type = 'customer_ids'
          and p.role = 'customer'
          and jsonb_typeof(p_audience->'customer_ids') = 'array'
          and c.id in (
            select value::uuid
            from jsonb_array_elements_text(p_audience->'customer_ids')
          )
        )
        or (
          audience_type = 'city'
          and p.role = 'customer'
          and nullif(trim(p_audience->>'city'), '') is not null
          and lower(trim(coalesce(c.city, ''))) =
            lower(trim(p_audience->>'city'))
        )
      )
    order by p.id
  loop
    perform public.enqueue_notification(
      recipient.id,
      recipient.role,
      p_type,
      trim(p_title),
      trim(p_body),
      p_payload || jsonb_build_object(
        'campaign_id', p_campaign_id,
        'type', p_type
      ),
      'campaign:' || p_campaign_id::text || ':' || recipient.id::text
    );
    recipient_count := recipient_count + 1;
  end loop;

  if recipient_count = 0 then
    raise exception using errcode = 'P0001', message = 'NO_CAMPAIGN_RECIPIENTS';
  end if;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    p_actor_id,
    'notification.campaign_sent',
    'notifications',
    null,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'notification_type', p_type,
      'audience', p_audience,
      'recipient_count', recipient_count
    )
  );

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'recipient_count', recipient_count,
    'queued', true
  );
end;
$$;

create or replace function public.claim_notification_outbox(
  p_worker_id text,
  p_limit integer default 25
)
returns table (
  outbox_id uuid,
  notification_id uuid,
  attempts integer
)
language sql
security definer
set search_path = public
as $$
  with candidates as (
    select o.id
    from public.notification_outbox o
    where (
      (
        o.status in ('pending','failed')
        and o.next_attempt_at <= now()
      )
      or (
        o.status = 'processing'
        and o.locked_at < now() - interval '10 minutes'
      )
    )
      and o.attempts < 10
    order by o.next_attempt_at, o.created_at
    for update skip locked
    limit greatest(least(p_limit, 100), 1)
  )
  update public.notification_outbox o
  set
    status = 'processing',
    attempts = o.attempts + 1,
    locked_at = now(),
    locked_by = p_worker_id,
    last_error = null
  from candidates c
  where o.id = c.id
  returning o.id, o.notification_id, o.attempts
$$;

revoke all on function public.app_setting_numeric(text, numeric) from public, anon, authenticated;
revoke all on function public.effective_product_price(uuid, uuid) from public, anon, authenticated;
revoke all on function public.enqueue_notification(uuid, text, text, text, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.order_payload(uuid) from public, anon, authenticated;
revoke all on function public.order_status_history_payload(uuid) from public, anon, authenticated;
revoke all on function public.place_order_transaction(uuid, uuid, jsonb, text, text, text) from public, anon, authenticated;
revoke all on function public.transition_order_status_transaction(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function public.redeem_invite_token(text, text, uuid) from public, anon, authenticated;
revoke all on function public.consume_edge_rate_limit(text, text, integer, integer) from public, anon, authenticated;
revoke all on function public.send_notification_campaign_transaction(uuid, uuid, text, text, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.claim_notification_outbox(text, integer) from public, anon, authenticated;

grant execute on function public.place_order_transaction(uuid, uuid, jsonb, text, text, text) to service_role;
grant execute on function public.transition_order_status_transaction(uuid, uuid, text, text) to service_role;
grant execute on function public.redeem_invite_token(text, text, uuid) to service_role;
grant execute on function public.consume_edge_rate_limit(text, text, integer, integer) to service_role;
grant execute on function public.send_notification_campaign_transaction(uuid, uuid, text, text, text, jsonb, jsonb) to service_role;
grant execute on function public.claim_notification_outbox(text, integer) to service_role;

alter table public.order_status_history enable row level security;
alter table public.inventory_reservations enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.notification_deliveries enable row level security;
alter table public.edge_rate_limits enable row level security;

drop policy if exists "customers create own orders" on public.orders;
drop policy if exists "staff manage orders" on public.orders;
drop policy if exists "customers insert own order items" on public.order_items;
drop policy if exists "staff manage order items" on public.order_items;
drop policy if exists "notifications staff insert" on public.notifications;
drop policy if exists "audit logs staff insert" on public.audit_logs;
drop policy if exists "invite tokens staff only" on public.invite_tokens;

drop policy if exists "order history own or staff read" on public.order_status_history;
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

drop policy if exists "inventory reservations staff read" on public.inventory_reservations;
create policy "inventory reservations staff read"
on public.inventory_reservations
for select
using (public.is_staff_or_admin());

drop policy if exists "device tokens owner read" on public.device_tokens;
create policy "device tokens owner read"
on public.device_tokens
for select
using (profile_id = auth.uid() or public.is_admin());

drop policy if exists "device tokens owner insert" on public.device_tokens;
create policy "device tokens owner insert"
on public.device_tokens
for insert
with check (profile_id = auth.uid() and public.is_active_actor());

drop policy if exists "device tokens owner update" on public.device_tokens;
create policy "device tokens owner update"
on public.device_tokens
for update
using (profile_id = auth.uid() and public.is_active_actor())
with check (profile_id = auth.uid() and public.is_active_actor());

drop policy if exists "device tokens owner delete" on public.device_tokens;
create policy "device tokens owner delete"
on public.device_tokens
for delete
using (profile_id = auth.uid());

drop policy if exists "notification outbox admin read" on public.notification_outbox;
create policy "notification outbox admin read"
on public.notification_outbox
for select
using (public.is_admin());

drop policy if exists "notification deliveries admin read" on public.notification_deliveries;
create policy "notification deliveries admin read"
on public.notification_deliveries
for select
using (public.is_admin());

drop policy if exists "invite tokens staff read" on public.invite_tokens;
create policy "invite tokens staff read"
on public.invite_tokens
for select
using (public.is_staff_or_admin());

notify pgrst, 'reload schema';
