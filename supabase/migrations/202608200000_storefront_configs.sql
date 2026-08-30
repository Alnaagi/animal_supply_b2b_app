-- Storefront designer: draft/publish config with validation and audit logs.
-- Customers read published config only via RPC; admin manages draft/publish.

create table if not exists public.storefront_configs (
  id text primary key default 'default' check (id = 'default'),
  draft_config jsonb not null default '{}'::jsonb,
  published_config jsonb not null default '{}'::jsonb,
  version integer not null default 1 check (version >= 1),
  updated_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default timezone('utc', now()),
  published_by uuid references public.profiles (id) on delete set null,
  published_at timestamptz
);

comment on table public.storefront_configs is
  'Singleton storefront layout/theme config. Draft is admin-only; customers use published_config.';

alter table public.storefront_configs enable row level security;

revoke all on table public.storefront_configs from public, anon, authenticated;
grant select, insert, update, delete on table public.storefront_configs to service_role;

create or replace function public.storefront_default_config_v1()
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'schemaVersion', 1,
    'theme', jsonb_build_object(
      'preset', 'default',
      'primaryColor', '#146c4e',
      'secondaryColor', '#8a623f',
      'backgroundColor', '#f5f0e8',
      'cardColor', '#ffffff',
      'textColor', '#1a3d2e'
    ),
    'style', jsonb_build_object(
      'cardRadius', 22,
      'buttonRadius', 18,
      'cardShadow', 'medium',
      'density', 'comfortable',
      'sectionSpacing', 14,
      'productImageRatio', 1.0
    ),
    'sections', jsonb_build_array(
      jsonb_build_object('type', 'header', 'visible', true, 'settings', jsonb_build_object(
        'showSearch', true, 'showNotifications', true, 'showLocation', true
      )),
      jsonb_build_object('type', 'banner', 'visible', true, 'settings', jsonb_build_object(
        'height', 88, 'autoPlay', true, 'intervalSeconds', 5,
        'borderRadius', 18, 'showIndicators', true
      )),
      jsonb_build_object('type', 'categories', 'visible', true, 'settings', jsonb_build_object(
        'title', 'التصنيفات', 'maxVisible', 20, 'showCount', true, 'layout', 'horizontal'
      )),
      jsonb_build_object('type', 'featured_products', 'visible', true, 'settings', jsonb_build_object(
        'title', '⭐ منتجات مميزة', 'maxItems', 12, 'showAddToCart', true, 'hideWhenEmpty', true
      )),
      jsonb_build_object('type', 'best_selling', 'visible', true, 'settings', jsonb_build_object(
        'title', 'الأكثر طلباً', 'maxItems', 12, 'fallbackToLatest', true, 'showAddToCart', true
      )),
      jsonb_build_object('type', 'offers', 'visible', true, 'settings', jsonb_build_object(
        'title', '🔥 العروض', 'maxItems', 12, 'showDiscountBadge', true, 'hideWhenEmpty', true
      )),
      jsonb_build_object('type', 'latest_products', 'visible', false, 'settings', jsonb_build_object(
        'title', 'أحدث المنتجات', 'maxItems', 12, 'showAddToCart', true
      )),
      jsonb_build_object('type', 'recent_order', 'visible', true, 'settings', jsonb_build_object(
        'title', 'إعادة آخر طلب', 'showItemCount', true
      ))
    )
  );
$$;

revoke all on function public.storefront_default_config_v1() from public, anon, authenticated;
grant execute on function public.storefront_default_config_v1() to authenticated, service_role;

create or replace function public.validate_storefront_config_v1(p_config jsonb)
returns void
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  section jsonb;
  section_type text;
  seen_types text[] := '{}';
  allowed_types constant text[] := array[
    'header', 'banner', 'categories', 'featured_products', 'offers',
    'best_selling', 'latest_products', 'recent_order'
  ];
  hex_pattern constant text := '^#[0-9A-Fa-f]{6}$';
  theme jsonb;
  style jsonb;
  numeric_value numeric;
begin
  if jsonb_typeof(p_config) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_CONFIG_INVALID';
  end if;

  if (p_config ->> 'schemaVersion')::integer is distinct from 1 then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_SCHEMA_UNSUPPORTED';
  end if;

  theme := p_config -> 'theme';
  if jsonb_typeof(theme) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_THEME_INVALID';
  end if;

  if (theme ->> 'primaryColor') !~ hex_pattern
    or (theme ->> 'secondaryColor') !~ hex_pattern
    or (theme ->> 'backgroundColor') !~ hex_pattern
    or (theme ->> 'cardColor') !~ hex_pattern
    or (theme ->> 'textColor') !~ hex_pattern then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_COLOR_INVALID';
  end if;

  if (theme ->> 'preset') not in ('default', 'clean', 'warm', 'modern') then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_PRESET_INVALID';
  end if;

  style := p_config -> 'style';
  if jsonb_typeof(style) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_STYLE_INVALID';
  end if;

  numeric_value := (style ->> 'cardRadius')::numeric;
  if numeric_value < 0 or numeric_value > 48 then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_STYLE_RANGE';
  end if;

  numeric_value := (style ->> 'buttonRadius')::numeric;
  if numeric_value < 0 or numeric_value > 48 then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_STYLE_RANGE';
  end if;

  if (style ->> 'cardShadow') not in ('none', 'light', 'medium', 'strong') then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_STYLE_INVALID';
  end if;

  if (style ->> 'density') not in ('compact', 'comfortable', 'spacious') then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_STYLE_INVALID';
  end if;

  numeric_value := (style ->> 'sectionSpacing')::numeric;
  if numeric_value < 4 or numeric_value > 48 then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_STYLE_RANGE';
  end if;

  numeric_value := (style ->> 'productImageRatio')::numeric;
  if numeric_value < 0.5 or numeric_value > 2.0 then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_STYLE_RANGE';
  end if;

  if jsonb_typeof(p_config -> 'sections') is distinct from 'array' then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_SECTIONS_INVALID';
  end if;

  for section in select value from jsonb_array_elements(p_config -> 'sections') loop
    section_type := section ->> 'type';
    if section_type is null or not (section_type = any (allowed_types)) then
      raise exception using errcode = 'P0001', message = 'STOREFRONT_SECTION_TYPE';
    end if;
    if section_type = any (seen_types) then
      raise exception using errcode = 'P0001', message = 'STOREFRONT_SECTION_DUPLICATE';
    end if;
    seen_types := array_append(seen_types, section_type);
    if jsonb_typeof(section -> 'settings') is distinct from 'object' then
      raise exception using errcode = 'P0001', message = 'STOREFRONT_SECTION_SETTINGS';
    end if;
    if section ? 'visible' and jsonb_typeof(section -> 'visible') is distinct from 'boolean' then
      raise exception using errcode = 'P0001', message = 'STOREFRONT_SECTION_VISIBLE';
    end if;
  end loop;

  if array_length(seen_types, 1) is distinct from array_length(allowed_types, 1) then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_SECTIONS_INCOMPLETE';
  end if;
end;
$$;

revoke all on function public.validate_storefront_config_v1(jsonb) from public, anon, authenticated;
grant execute on function public.validate_storefront_config_v1(jsonb) to authenticated, service_role;

create or replace function public.get_published_storefront_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  result jsonb;
begin
  if not public.is_active_actor() then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;

  select sc.published_config
  into result
  from public.storefront_configs sc
  where sc.id = 'default';

  if result is null or result = '{}'::jsonb then
    return public.storefront_default_config_v1();
  end if;

  perform public.validate_storefront_config_v1(result);
  return result;
exception
  when others then
    return public.storefront_default_config_v1();
end;
$$;

comment on function public.get_published_storefront_config() is
  'Returns published storefront config for customers/staff; falls back to bundled default.';

grant execute on function public.get_published_storefront_config() to authenticated;

create or replace function public.get_storefront_admin_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  row_data public.storefront_configs%rowtype;
  default_cfg jsonb := public.storefront_default_config_v1();
begin
  if not public.is_admin() then
    raise exception using errcode = 'P0001', message = 'ADMIN_REQUIRED';
  end if;

  select *
  into row_data
  from public.storefront_configs sc
  where sc.id = 'default';

  if not found then
    return jsonb_build_object(
      'draftConfig', default_cfg,
      'publishedConfig', default_cfg,
      'version', 1,
      'updatedAt', null,
      'publishedAt', null,
      'hasDraftChanges', false
    );
  end if;

  return jsonb_build_object(
    'draftConfig', case
      when row_data.draft_config = '{}'::jsonb then default_cfg
      else row_data.draft_config
    end,
    'publishedConfig', case
      when row_data.published_config = '{}'::jsonb then default_cfg
      else row_data.published_config
    end,
    'version', row_data.version,
    'updatedAt', row_data.updated_at,
    'publishedAt', row_data.published_at,
    'hasDraftChanges', row_data.draft_config is distinct from row_data.published_config
  );
end;
$$;

grant execute on function public.get_storefront_admin_state() to authenticated;

create or replace function public.admin_save_storefront_draft(
  p_config jsonb,
  p_expected_updated_at timestamptz default null
)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  current_row public.storefront_configs%rowtype;
  new_updated_at timestamptz := timezone('utc', now());
begin
  if not public.is_admin() then
    raise exception using errcode = 'P0001', message = 'ADMIN_REQUIRED';
  end if;

  perform public.validate_storefront_config_v1(p_config);

  lock table public.storefront_configs in exclusive mode;

  select *
  into current_row
  from public.storefront_configs sc
  where sc.id = 'default'
  for update;

  if found then
    perform public.assert_fresh_updated_at(
      current_row.updated_at,
      p_expected_updated_at
    );

    update public.storefront_configs sc
    set
      draft_config = p_config,
      version = sc.version + 1,
      updated_by = actor_id,
      updated_at = new_updated_at
    where sc.id = 'default';
  else
    insert into public.storefront_configs (
      id,
      draft_config,
      published_config,
      version,
      updated_by,
      updated_at
    )
    values (
      'default',
      p_config,
      public.storefront_default_config_v1(),
      1,
      actor_id,
      new_updated_at
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
    actor_id,
    'storefront.draft_updated',
    'storefront_configs',
    null,
    jsonb_build_object(
      'configId', 'default',
      'schemaVersion', p_config -> 'schemaVersion',
      'sectionCount', jsonb_array_length(p_config -> 'sections')
    )
  );

  return new_updated_at;
end;
$$;

grant execute on function public.admin_save_storefront_draft(jsonb, timestamptz) to authenticated;

create or replace function public.admin_publish_storefront(
  p_expected_updated_at timestamptz default null
)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  current_row public.storefront_configs%rowtype;
  publish_at timestamptz := timezone('utc', now());
begin
  if not public.is_admin() then
    raise exception using errcode = 'P0001', message = 'ADMIN_REQUIRED';
  end if;

  lock table public.storefront_configs in exclusive mode;

  select *
  into current_row
  from public.storefront_configs sc
  where sc.id = 'default'
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_NOT_FOUND';
  end if;

  perform public.assert_fresh_updated_at(
    current_row.updated_at,
    p_expected_updated_at
  );

  perform public.validate_storefront_config_v1(current_row.draft_config);

  update public.storefront_configs sc
  set
    published_config = current_row.draft_config,
    published_by = actor_id,
    published_at = publish_at,
    updated_by = actor_id,
    updated_at = publish_at,
    version = sc.version + 1
  where sc.id = 'default';

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    actor_id,
    'storefront.published',
    'storefront_configs',
    null,
    jsonb_build_object(
      'configId', 'default',
      'publishedAt', publish_at,
      'version', current_row.version + 1
    )
  );

  return publish_at;
end;
$$;

grant execute on function public.admin_publish_storefront(timestamptz) to authenticated;

create or replace function public.admin_reset_storefront_draft(
  p_expected_updated_at timestamptz default null
)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  current_row public.storefront_configs%rowtype;
  reset_at timestamptz := timezone('utc', now());
  published_cfg jsonb;
begin
  if not public.is_admin() then
    raise exception using errcode = 'P0001', message = 'ADMIN_REQUIRED';
  end if;

  lock table public.storefront_configs in exclusive mode;

  select *
  into current_row
  from public.storefront_configs sc
  where sc.id = 'default'
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOREFRONT_NOT_FOUND';
  end if;

  perform public.assert_fresh_updated_at(
    current_row.updated_at,
    p_expected_updated_at
  );

  published_cfg := case
    when current_row.published_config = '{}'::jsonb
      then public.storefront_default_config_v1()
    else current_row.published_config
  end;

  perform public.validate_storefront_config_v1(published_cfg);

  update public.storefront_configs sc
  set
    draft_config = published_cfg,
    updated_by = actor_id,
    updated_at = reset_at,
    version = sc.version + 1
  where sc.id = 'default';

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    actor_id,
    'storefront.reset',
    'storefront_configs',
    null,
    jsonb_build_object(
      'configId', 'default',
      'resetTo', 'published'
    )
  );

  return reset_at;
end;
$$;

grant execute on function public.admin_reset_storefront_draft(timestamptz) to authenticated;

-- Seed singleton row with default published config; draft matches published (no live change).
insert into public.storefront_configs (
  id,
  draft_config,
  published_config,
  version,
  updated_at,
  published_at
)
values (
  'default',
  public.storefront_default_config_v1(),
  public.storefront_default_config_v1(),
  1,
  timezone('utc', now()),
  timezone('utc', now())
)
on conflict (id) do nothing;
