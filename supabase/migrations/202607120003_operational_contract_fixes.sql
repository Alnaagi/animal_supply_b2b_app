-- Align production UI contracts with the secured notification/order backend.
-- This migration is additive and safe to apply after the hardening chain.

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

    if coalesce(cardinality(audience_roles), 0) <> jsonb_array_length(p_audience->'roles') then
      raise exception using errcode = 'P0001', message = 'INVALID_CAMPAIGN_ROLE';
    end if;
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
