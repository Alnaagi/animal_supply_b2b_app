\set ON_ERROR_STOP on

-- Rollback-only checks for customer last-seen / last-active helpers.

begin;

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'last_seen_at'
  ) then
    raise exception 'profiles.last_seen_at is missing';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.touch_own_last_seen()',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute touch_own_last_seen';
  end if;

  if has_function_privilege(
    'anon',
    'public.touch_own_last_seen()',
    'EXECUTE'
  ) then
    raise exception 'anon unexpectedly executes touch_own_last_seen';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.customer_last_active_at(profiles)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute customer_last_active_at';
  end if;

  if has_function_privilege(
    'anon',
    'public.customer_last_active_at(profiles)',
    'EXECUTE'
  ) then
    raise exception 'anon unexpectedly executes customer_last_active_at';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.sync_profile_last_seen_from_device_token()',
    'EXECUTE'
  ) then
    raise exception 'authenticated unexpectedly executes device last-seen trigger';
  end if;
end;
$$;

rollback;
