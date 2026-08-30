\set ON_ERROR_STOP on

-- Verification for migration 20260822164609_banners_archive_support.
--
-- Required psql variables:
--   admin_profile_id     active admin profile UUID
--   customer_profile_id  active customer profile UUID

begin;

select set_config('test.admin_profile_id', :'admin_profile_id', true);
select set_config('test.customer_profile_id', :'customer_profile_id', true);

do $$
declare
  v_admin uuid := current_setting('test.admin_profile_id')::uuid;
  v_customer uuid := current_setting('test.customer_profile_id')::uuid;
  v_banner_id uuid;
  v_visible_count integer;
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'banners'
      and column_name = 'archived_at'
  ) then
    raise exception 'banners.archived_at column is missing';
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  insert into public.banners (
    title, image_url, cta_text, target_type, sort_order, active, archived_at
  ) values (
    'اختبار أرشفة بانر',
    'https://cdn.example.com/banner-archive-test.webp',
    'عرض',
    'catalog',
    9999,
    true,
    null
  ) returning id into v_banner_id;

  update public.banners
  set archived_at = now(), active = false
  where id = v_banner_id;

  perform set_config('request.jwt.claim.sub', v_customer::text, true);

  select count(*) into v_visible_count
  from public.banners
  where id = v_banner_id;

  if v_visible_count <> 0 then
    raise exception 'Customer can still read an archived banner';
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  select count(*) into v_visible_count
  from public.banners
  where id = v_banner_id;

  if v_visible_count <> 1 then
    raise exception 'Admin cannot read an archived banner';
  end if;

  delete from public.banners where id = v_banner_id;

  select count(*) into v_visible_count
  from public.banners
  where id = v_banner_id;

  if v_visible_count <> 0 then
    raise exception 'Admin hard delete of banner failed';
  end if;
end $$;

rollback;
