-- Authenticated inbox reads and mark-all-read stay scoped to auth.uid().
-- Direct table SELECT already has RLS; these RPCs make the contract explicit
-- and avoid client count/filter quirks emptying the in-app list.
--
-- Inbox RPCs intentionally do not call is_active_actor(). Catalog/orders use
-- SECURITY DEFINER helpers, so a false is_active_actor() would hide the bell
-- list while the rest of the app still worked.

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
set search_path = public, pg_temp
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

create or replace function public.list_my_notifications(
  p_limit integer default 50
)
returns table (
  id uuid,
  type text,
  title text,
  body text,
  payload jsonb,
  read_at timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  return query
  select
    n.id,
    n.type,
    n.title,
    n.body,
    n.payload,
    n.read_at,
    n.created_at
  from public.notifications n
  where n.recipient_profile_id = auth.uid()
  order by n.created_at desc
  limit greatest(least(coalesce(p_limit, 50), 100), 1);
end;
$$;

create or replace function public.unread_notification_count()
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    return 0;
  end if;

  return (
    select count(*)::integer
    from public.notifications n
    where n.recipient_profile_id = auth.uid()
      and n.read_at is null
  );
end;
$$;

create or replace function public.mark_all_my_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated integer := 0;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;

  update public.notifications n
  set read_at = now()
  where n.recipient_profile_id = auth.uid()
    and n.read_at is null;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

revoke all on function public.enqueue_notification(
  uuid, text, text, text, text, jsonb, text
) from public, anon, authenticated;
grant execute on function public.enqueue_notification(
  uuid, text, text, text, text, jsonb, text
) to service_role;

revoke all on function public.list_my_notifications(integer)
  from public, anon;
grant execute on function public.list_my_notifications(integer)
  to authenticated;

revoke all on function public.unread_notification_count()
  from public, anon;
grant execute on function public.unread_notification_count()
  to authenticated;

revoke all on function public.mark_all_my_notifications_read()
  from public, anon;
grant execute on function public.mark_all_my_notifications_read()
  to authenticated;

grant execute on function public.current_role() to authenticated;
grant execute on function public.is_active_actor() to authenticated;

notify pgrst, 'reload schema';
