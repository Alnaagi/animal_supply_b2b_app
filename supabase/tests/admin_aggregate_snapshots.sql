\set ON_ERROR_STOP on

-- Manual authenticated-role verification for migration 029.
--
-- Required psql variables:
--   admin_profile_id     active admin profile UUID
--   staff_profile_id     active staff profile UUID
--   customer_profile_id  active customer profile UUID
--
-- Example:
--   psql "$DATABASE_URL" \
--     -f supabase/tests/admin_aggregate_snapshots.sql \
--     -v admin_profile_id=... \
--     -v staff_profile_id=... \
--     -v customer_profile_id=...

begin;
set local role authenticated;

select set_config(
  'request.jwt.claim.sub',
  :'staff_profile_id',
  true
);

do $$
declare
  dashboard jsonb;
begin
  dashboard := public.admin_dashboard_snapshot();
  if not dashboard ? 'stats'
    or jsonb_typeof(dashboard -> 'pending_orders') <> 'array'
    or jsonb_typeof(dashboard -> 'low_stock_products') <> 'array'
  then
    raise exception 'Invalid staff dashboard snapshot shape';
  end if;

  begin
    perform public.admin_operational_report(null, null);
    raise exception 'Staff unexpectedly accessed the admin-only report';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  :'admin_profile_id',
  true
);

do $$
declare
  dashboard jsonb;
  report jsonb;
begin
  dashboard := public.admin_dashboard_snapshot();
  report := public.admin_operational_report(
    now() - interval '30 days',
    now()
  );

  if not dashboard ? 'stats' then
    raise exception 'Admin dashboard snapshot is missing stats';
  end if;
  if not report ? 'period_order_count'
    or jsonb_typeof(report -> 'top_customers') <> 'array'
    or jsonb_typeof(report -> 'top_products') <> 'array'
  then
    raise exception 'Invalid admin operational report shape';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  :'customer_profile_id',
  true
);

do $$
begin
  begin
    perform public.admin_dashboard_snapshot();
    raise exception 'Customer unexpectedly accessed the admin dashboard';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.admin_operational_report(null, null);
    raise exception 'Customer unexpectedly accessed the admin report';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

rollback;
