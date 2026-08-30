-- Staff-visible customer last activity from real timestamps:
-- auth.users.last_sign_in_at, device_tokens.last_seen_at, last order,
-- and a denormalized profiles.last_seen_at kept in sync from login/app use.
-- Flutter never receives the service role key.

alter table public.profiles
  add column if not exists last_seen_at timestamptz;

comment on column public.profiles.last_seen_at is
  'Latest app presence for this profile. Staff/admin read it; clients update only through SECURITY DEFINER helpers.';

update public.profiles p
set
  last_login_at = coalesce(p.last_login_at, src.last_sign_in_at),
  last_seen_at = src.last_active_at
from (
  select
    profile.id,
    auth_user.last_sign_in_at,
    greatest(
      profile.last_login_at,
      profile.last_seen_at,
      auth_user.last_sign_in_at,
      device_seen.max_seen_at,
      last_order.max_created_at
    ) as last_active_at
  from public.profiles profile
  left join auth.users auth_user
    on auth_user.id = profile.id
  left join (
    select
      dt.profile_id,
      max(dt.last_seen_at) as max_seen_at
    from public.device_tokens dt
    group by dt.profile_id
  ) device_seen
    on device_seen.profile_id = profile.id
  left join (
    select
      o.customer_profile_id as profile_id,
      max(o.created_at) as max_created_at
    from public.orders o
    where o.customer_profile_id is not null
    group by o.customer_profile_id
  ) last_order
    on last_order.profile_id = profile.id
) src
where p.id = src.id
  and src.last_active_at is not null
  and (
    p.last_seen_at is distinct from src.last_active_at
    or p.last_login_at is distinct from coalesce(p.last_login_at, src.last_sign_in_at)
  );

create or replace function public.customer_last_active_at(p public.profiles)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.role() = 'anon' then
    return null;
  end if;

  if auth.uid() is not null
    and p.id is distinct from auth.uid()
    and not public.is_staff_or_admin()
  then
    return null;
  end if;

  return greatest(
    p.last_seen_at,
    p.last_login_at,
    (
      select auth_user.last_sign_in_at
      from auth.users auth_user
      where auth_user.id = p.id
    ),
    (
      select max(dt.last_seen_at)
      from public.device_tokens dt
      where dt.profile_id = p.id
    ),
    (
      select max(o.created_at)
      from public.orders o
      where o.customer_profile_id = p.id
    )
  );
end;
$$;

revoke all on function public.customer_last_active_at(public.profiles)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_last_active_at(public.profiles)
  to authenticated;

comment on function public.customer_last_active_at(public.profiles) is
  'Staff/admin (or the profile owner) last-active timestamp from login, device presence, last_seen, and last order.';

create or replace function public.touch_own_last_seen()
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_last_seen timestamptz;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;

  select p.last_seen_at
  into v_last_seen
  from public.profiles p
  where p.id = auth.uid();

  if not found then
    raise exception using errcode = 'P0001', message = 'PROFILE_REQUIRED';
  end if;

  if v_last_seen is not null
    and v_last_seen > v_now - interval '2 minutes'
  then
    return v_last_seen;
  end if;

  update public.profiles
  set last_seen_at = v_now
  where id = auth.uid()
  returning last_seen_at into v_last_seen;

  return v_last_seen;
end;
$$;

revoke all on function public.touch_own_last_seen()
  from public, anon, authenticated, service_role;
grant execute on function public.touch_own_last_seen()
  to authenticated;

comment on function public.touch_own_last_seen() is
  'Authenticated users record their own app presence on profiles.last_seen_at, rate-limited to two minutes.';

create or replace function public.sync_profile_last_seen_from_device_token()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.profile_id is null or new.last_seen_at is null then
    return new;
  end if;

  update public.profiles
  set last_seen_at = greatest(coalesce(last_seen_at, new.last_seen_at), new.last_seen_at)
  where id = new.profile_id
    and (
      last_seen_at is null
      or last_seen_at < new.last_seen_at
    );

  return new;
end;
$$;

drop trigger if exists sync_profile_last_seen_from_device_token
  on public.device_tokens;
create trigger sync_profile_last_seen_from_device_token
after insert or update of last_seen_at on public.device_tokens
for each row
execute function public.sync_profile_last_seen_from_device_token();

create or replace function public.sync_profile_last_seen_from_auth_users()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.last_sign_in_at is null then
    return new;
  end if;

  if tg_op = 'UPDATE'
    and new.last_sign_in_at is not distinct from old.last_sign_in_at
  then
    return new;
  end if;

  update public.profiles
  set
    last_login_at = new.last_sign_in_at,
    last_seen_at = greatest(
      coalesce(last_seen_at, new.last_sign_in_at),
      new.last_sign_in_at
    )
  where id = new.id;

  return new;
end;
$$;

drop trigger if exists sync_profile_last_seen_from_auth_users
  on auth.users;
create trigger sync_profile_last_seen_from_auth_users
after insert or update of last_sign_in_at on auth.users
for each row
execute function public.sync_profile_last_seen_from_auth_users();

revoke all on function public.sync_profile_last_seen_from_device_token()
  from public, anon, authenticated;
revoke all on function public.sync_profile_last_seen_from_auth_users()
  from public, anon, authenticated;
