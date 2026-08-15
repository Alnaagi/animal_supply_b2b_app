-- Make notification campaigns retry-safe and keep device registration bounded.
-- This migration is additive and must be applied after the production
-- hardening and operational contract migrations.

create table if not exists public.notification_campaigns (
  id uuid primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  notification_type text not null,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  audience jsonb not null,
  recipient_count integer not null default 0 check (recipient_count >= 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_notification_campaigns_created
  on public.notification_campaigns(created_at desc);

create index if not exists idx_notifications_campaign_id
  on public.notifications ((payload->>'campaign_id'))
  where payload ? 'campaign_id';

alter table public.notification_campaigns enable row level security;

-- Device-token writes must pass through the rate-limited Edge Functions and
-- the bounded registration transaction below. Older owner CRUD grants would
-- otherwise let an authenticated client bypass those controls.
drop policy if exists "device tokens owner read" on public.device_tokens;
drop policy if exists "device tokens owner insert" on public.device_tokens;
drop policy if exists "device tokens owner update" on public.device_tokens;
drop policy if exists "device tokens owner delete" on public.device_tokens;
revoke all on public.device_tokens from anon, authenticated;

drop policy if exists "notification campaigns admin read"
  on public.notification_campaigns;
create policy "notification campaigns admin read"
on public.notification_campaigns
for select
using (public.is_admin());

revoke insert, update, delete
  on public.notification_campaigns
  from anon, authenticated;
grant select on public.notification_campaigns to authenticated;

create or replace function public.register_device_token_transaction(
  p_profile_id uuid,
  p_token text,
  p_platform text,
  p_device_id text,
  p_device_label text,
  p_app_version text,
  p_locale text,
  p_max_active integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  saved_token public.device_tokens%rowtype;
  deactivated_count integer := 0;
  active_device_count integer := 0;
begin
  if not exists (
    select 1
    from public.profiles p
    where p.id = p_profile_id
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
  ) then
    raise exception using errcode = 'P0001', message = 'PROFILE_INACTIVE';
  end if;

  if p_profile_id is null
    or nullif(trim(p_token), '') is null
    or length(trim(p_token)) < 20
    or length(trim(p_token)) > 4096
    or p_platform is null
    or p_platform not in ('android', 'ios', 'web')
    or p_max_active is null
    or p_max_active < 1
    or p_max_active > 20
    or length(coalesce(p_device_id, '')) > 200
    or length(coalesce(p_device_label, '')) > 200
    or length(coalesce(p_app_version, '')) > 50
    or length(coalesce(p_locale, '')) > 20
  then
    raise exception using errcode = 'P0001', message = 'INVALID_DEVICE_TOKEN';
  end if;

  -- Serialize registrations for one profile so concurrent token refreshes
  -- cannot bypass the active-device cap.
  perform pg_advisory_xact_lock(hashtextextended(p_profile_id::text, 0));

  if nullif(trim(p_device_id), '') is not null then
    update public.device_tokens
    set
      active = false,
      updated_at = now()
    where profile_id = p_profile_id
      and device_id = trim(p_device_id)
      and token <> trim(p_token)
      and active;
  end if;

  insert into public.device_tokens (
    profile_id,
    token,
    platform,
    device_id,
    device_label,
    app_version,
    locale,
    active,
    last_seen_at,
    updated_at
  )
  values (
    p_profile_id,
    trim(p_token),
    p_platform,
    nullif(trim(p_device_id), ''),
    nullif(trim(p_device_label), ''),
    nullif(trim(p_app_version), ''),
    coalesce(nullif(trim(p_locale), ''), 'ar_LY'),
    true,
    now(),
    now()
  )
  on conflict (token) do update set
    profile_id = excluded.profile_id,
    platform = excluded.platform,
    device_id = excluded.device_id,
    device_label = excluded.device_label,
    app_version = excluded.app_version,
    locale = excluded.locale,
    active = true,
    last_seen_at = now(),
    updated_at = now()
  returning * into saved_token;

  with excess_tokens as (
    select dt.id
    from public.device_tokens dt
    where dt.profile_id = p_profile_id
      and dt.active
      and dt.id <> saved_token.id
    order by dt.last_seen_at desc, dt.created_at desc, dt.id
    offset greatest(p_max_active - 1, 0)
  )
  update public.device_tokens dt
  set
    active = false,
    updated_at = now()
  where dt.id in (select id from excess_tokens);

  get diagnostics deactivated_count = row_count;

  select count(*)::integer
  into active_device_count
  from public.device_tokens dt
  where dt.profile_id = p_profile_id
    and dt.active;

  return jsonb_build_object(
    'device_token', to_jsonb(saved_token),
    'active_device_count', active_device_count,
    'deactivated_device_count', deactivated_count
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
  audience_roles text[];
  recipient record;
  v_recipient_count integer := 0;
  campaign_row public.notification_campaigns%rowtype;
begin
  select p.role
  into actor_role
  from public.profiles p
  where p.id = p_actor_id
    and p.active
    and not p.must_change_password
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
    or audience_type not in (
      'all',
      'role',
      'roles',
      'profile_ids',
      'customer_ids',
      'city'
    )
  then
    raise exception using errcode = 'P0001', message = 'INVALID_CAMPAIGN_AUDIENCE';
  end if;

  audience_role := p_audience->>'role';
  if audience_type = 'role'
    and (
      audience_role is null
      or audience_role not in ('admin', 'staff', 'customer')
    )
  then
    raise exception using errcode = 'P0001', message = 'INVALID_CAMPAIGN_ROLE';
  end if;

  if audience_type = 'roles' then
    if jsonb_typeof(p_audience->'roles') <> 'array'
      or jsonb_array_length(p_audience->'roles') = 0
      or jsonb_array_length(p_audience->'roles') > 3
    then
      raise exception using errcode = 'P0001', message = 'INVALID_CAMPAIGN_ROLE';
    end if;

    select array_agg(distinct roles.value)
    into audience_roles
    from jsonb_array_elements_text(p_audience->'roles') as roles(value)
    where roles.value in ('admin', 'staff', 'customer');

    if coalesce(cardinality(audience_roles), 0) <>
      jsonb_array_length(p_audience->'roles')
    then
      raise exception using errcode = 'P0001', message = 'INVALID_CAMPAIGN_ROLE';
    end if;
  end if;

  insert into public.notification_campaigns (
    id,
    actor_id,
    notification_type,
    title,
    body,
    payload,
    audience
  )
  values (
    p_campaign_id,
    p_actor_id,
    p_type,
    trim(p_title),
    trim(p_body),
    p_payload,
    p_audience
  )
  on conflict (id) do nothing
  returning * into campaign_row;

  if campaign_row.id is null then
    select *
    into campaign_row
    from public.notification_campaigns c
    where c.id = p_campaign_id;

    if campaign_row.id is null then
      raise exception using errcode = 'P0001', message = 'CAMPAIGN_ID_CONFLICT';
    end if;

    if campaign_row.actor_id is distinct from p_actor_id
      or campaign_row.notification_type is distinct from p_type
      or campaign_row.title is distinct from trim(p_title)
      or campaign_row.body is distinct from trim(p_body)
      or campaign_row.payload is distinct from p_payload
      or campaign_row.audience is distinct from p_audience
    then
      raise exception using errcode = 'P0001', message = 'CAMPAIGN_ID_CONFLICT';
    end if;

    return jsonb_build_object(
      'campaign_id', campaign_row.id,
      'recipient_count', campaign_row.recipient_count,
      'queued', true,
      'idempotent', true
    );
  end if;

  for recipient in
    select distinct p.id, p.role
    from public.profiles p
    left join public.business_customers c on c.profile_id = p.id
    where p.active
      and not p.must_change_password
      and (
        p.role <> 'customer'
        or (
          c.account_status = 'active'
          and c.archived_at is null
        )
      )
      and (
        audience_type = 'all'
        or (
          audience_type = 'role'
          and p.role = audience_role
        )
        or (
          audience_type = 'roles'
          and p.role = any(audience_roles)
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
    v_recipient_count := v_recipient_count + 1;
  end loop;

  if v_recipient_count = 0 then
    raise exception using errcode = 'P0001', message = 'NO_CAMPAIGN_RECIPIENTS';
  end if;

  update public.notification_campaigns
  set recipient_count = v_recipient_count
  where id = p_campaign_id;

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
    'notification_campaigns',
    p_campaign_id,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'notification_type', p_type,
      'audience', p_audience,
      'recipient_count', v_recipient_count
    )
  );

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'recipient_count', v_recipient_count,
    'queued', true,
    'idempotent', false
  );
end;
$$;

create or replace function public.notification_campaign_summaries(
  p_limit integer default 10
)
returns table (
  campaign_id uuid,
  title text,
  body text,
  notification_type text,
  audience jsonb,
  recipient_count integer,
  completed_count bigint,
  pending_count bigint,
  retrying_count bigint,
  dead_count bigint,
  device_sent_count bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception using errcode = 'P0001', message = 'ADMIN_AUTH_REQUIRED';
  end if;

  return query
  select
    c.id,
    c.title,
    c.body,
    c.notification_type,
    c.audience,
    c.recipient_count,
    coalesce(outbox.completed_count, 0),
    coalesce(outbox.pending_count, 0),
    coalesce(outbox.retrying_count, 0),
    coalesce(outbox.dead_count, 0),
    coalesce(deliveries.device_sent_count, 0),
    c.created_at
  from public.notification_campaigns c
  left join lateral (
    select
      count(*) filter (where o.status = 'sent') as completed_count,
      count(*) filter (where o.status in ('pending', 'processing'))
        as pending_count,
      count(*) filter (where o.status = 'failed') as retrying_count,
      count(*) filter (where o.status = 'dead') as dead_count
    from public.notifications n
    join public.notification_outbox o on o.notification_id = n.id
    where n.payload->>'campaign_id' = c.id::text
  ) outbox on true
  left join lateral (
    select count(*) filter (where d.status = 'sent') as device_sent_count
    from public.notifications n
    join public.notification_outbox o on o.notification_id = n.id
    join public.notification_deliveries d on d.outbox_id = o.id
    where n.payload->>'campaign_id' = c.id::text
  ) deliveries on true
  order by c.created_at desc
  limit greatest(least(coalesce(p_limit, 10), 50), 1);
end;
$$;

revoke all on function public.register_device_token_transaction(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  integer
) from public, anon, authenticated;
grant execute on function public.register_device_token_transaction(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  integer
) to service_role;

revoke all on function public.notification_campaign_summaries(integer)
  from public, anon, authenticated;
grant execute on function public.notification_campaign_summaries(integer)
  to authenticated;

notify pgrst, 'reload schema';
