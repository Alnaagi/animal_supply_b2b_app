-- Fix storefront save/publish/reset: audit_logs.entity_id is uuid, but RPCs
-- inserted the text singleton key 'default', which rolls back every mutation
-- with: invalid input syntax for type uuid: "default".
-- Use null entity_id and record the config key in metadata instead.

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

grant execute on function public.admin_publish_storefront(timestamptz, jsonb) to authenticated;

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
