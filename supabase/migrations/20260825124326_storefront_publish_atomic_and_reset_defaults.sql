-- Atomic storefront publish (optional draft payload) + reset draft to bundled defaults.
-- Publish with p_draft_config writes draft then publishes under one lock so color-only
-- publishes no longer fail when the client skipped a separate save or round-tripped
-- expected_updated_at incorrectly between two RPCs.

drop function if exists public.admin_publish_storefront(timestamptz);
drop function if exists public.admin_publish_storefront(timestamptz, jsonb);

create or replace function public.admin_publish_storefront(
  p_expected_updated_at timestamptz default null,
  p_draft_config jsonb default null
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
  draft_to_publish jsonb;
begin
  if not public.is_admin() then
    raise exception using errcode = 'P0001', message = 'ADMIN_REQUIRED';
  end if;

  if p_draft_config is not null then
    perform public.validate_storefront_config_v1(p_draft_config);
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

  draft_to_publish := coalesce(p_draft_config, current_row.draft_config);

  if draft_to_publish is null or draft_to_publish = '{}'::jsonb then
    draft_to_publish := public.storefront_default_config_v1();
  end if;

  perform public.validate_storefront_config_v1(draft_to_publish);

  update public.storefront_configs sc
  set
    draft_config = draft_to_publish,
    published_config = draft_to_publish,
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
      'version', current_row.version + 1,
      'atomicDraft', p_draft_config is not null
    )
  );

  return publish_at;
end;
$$;

comment on function public.admin_publish_storefront(timestamptz, jsonb) is
  'Publishes storefront draft; optional p_draft_config saves+publishes atomically.';

grant execute on function public.admin_publish_storefront(timestamptz, jsonb) to authenticated;

-- Reset draft to bundled factory defaults (not published snapshot).
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
  default_cfg jsonb := public.storefront_default_config_v1();
begin
  if not public.is_admin() then
    raise exception using errcode = 'P0001', message = 'ADMIN_REQUIRED';
  end if;

  perform public.validate_storefront_config_v1(default_cfg);

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

  update public.storefront_configs sc
  set
    draft_config = default_cfg,
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
      'resetTo', 'default'
    )
  );

  return reset_at;
end;
$$;

grant execute on function public.admin_reset_storefront_draft(timestamptz) to authenticated;
