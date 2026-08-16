-- Privileged database disk usage for the admin dashboard.
-- Callable only with the service role from an Edge Function.

create or replace function public.admin_database_usage()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  return jsonb_build_object(
    'used_bytes', pg_database_size(current_database())
  );
end;
$$;

comment on function public.admin_database_usage() is
  'Returns live Postgres database size in bytes. Execute is granted only to service_role.';

revoke all on function public.admin_database_usage() from public, anon, authenticated;
grant execute on function public.admin_database_usage() to service_role;
