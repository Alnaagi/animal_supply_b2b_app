-- DEPRECATED AND INTENTIONALLY FAIL-CLOSED.
--
-- RLS is defined only by the ordered files in supabase/migrations. This path
-- remains as a guard for old deployment notes and must never be used as a
-- bootstrap or production policy source.

do $$
begin
  raise exception using
    errcode = 'P0001',
    message = 'RLS_SQL_DEPRECATED_USE_SUPABASE_MIGRATIONS';
end
$$;
