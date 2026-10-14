-- Verification for migration 20260823210000_banner_aspect_mode.

begin;

do $$
declare
  v_banner_id uuid;
  v_mode text;
  v_default text;
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'banners'
      and column_name = 'aspect_mode'
  ) then
    raise exception 'banners.aspect_mode column is missing';
  end if;

  insert into public.banners (
    title, image_url, cta_text, target_type, sort_order, active
  ) values (
    'aspect-mode-default-test',
    'https://cdn.example.com/banner.webp',
    'اطلب الآن',
    'catalog',
    0,
    true
  )
  returning id, aspect_mode into v_banner_id, v_default;

  if v_default is distinct from 'wide' then
    raise exception 'expected default aspect_mode wide, got %', v_default;
  end if;

  update public.banners
  set aspect_mode = 'square'
  where id = v_banner_id
  returning aspect_mode into v_mode;

  if v_mode is distinct from 'square' then
    raise exception 'expected aspect_mode square after update, got %', v_mode;
  end if;

  begin
    update public.banners
    set aspect_mode = 'invalid'
    where id = v_banner_id;
    raise exception 'aspect_mode check constraint did not reject invalid value';
  exception
    when check_violation then
      null;
  end;

  delete from public.banners where id = v_banner_id;
end $$;

rollback;
