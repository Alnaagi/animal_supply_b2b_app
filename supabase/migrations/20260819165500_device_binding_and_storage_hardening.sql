-- Harden customer device binding and storage object path checks.
-- Keep existing behavior for staff/admin while enforcing one-device binding for
-- customers through the service-role registration transaction.

alter table public.device_tokens
  add column if not exists installation_id_hash text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'device_tokens_installation_id_hash_format'
      and conrelid = 'public.device_tokens'::regclass
  ) then
    alter table public.device_tokens
      add constraint device_tokens_installation_id_hash_format
      check (
        installation_id_hash is null
        or installation_id_hash ~ '^[0-9a-f]{64}$'
      );
  end if;
end;
$$;

create index if not exists idx_device_tokens_profile_installation_active
  on public.device_tokens(profile_id, installation_id_hash)
  where active;

create or replace function public.register_device_token_transaction(
  p_profile_id uuid,
  p_token text,
  p_platform text,
  p_device_id text,
  p_installation_id_hash text,
  p_device_label text,
  p_app_version text,
  p_locale text,
  p_max_active integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  saved_token public.device_tokens%rowtype;
  deactivated_count integer := 0;
  active_device_count integer := 0;
  caller_role text;
begin
  select p.role
  into caller_role
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
    );

  if caller_role is null then
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
    or (
      p_installation_id_hash is not null
      and p_installation_id_hash !~ '^[0-9a-f]{64}$'
    )
  then
    raise exception using errcode = 'P0001', message = 'INVALID_DEVICE_TOKEN';
  end if;

  if caller_role = 'customer' and nullif(trim(coalesce(p_installation_id_hash, '')), '') is null then
    raise exception using errcode = 'P0001', message = 'INVALID_DEVICE_TOKEN';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_profile_id::text, 0));

  if caller_role = 'customer' then
    update public.device_tokens
    set
      active = false,
      updated_at = now()
    where profile_id = p_profile_id
      and active
      and (
        installation_id_hash is distinct from p_installation_id_hash
        or token <> trim(p_token)
      );
  elsif nullif(trim(p_device_id), '') is not null then
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
    installation_id_hash,
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
    nullif(trim(coalesce(p_installation_id_hash, '')), ''),
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
    installation_id_hash = excluded.installation_id_hash,
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

revoke all on function public.register_device_token_transaction(
  uuid,
  text,
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
  text,
  integer
) to service_role;

create or replace function public.admin_reset_customer_device_binding(
  p_actor_id uuid,
  p_customer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target_profile_id uuid;
  changed_rows integer := 0;
begin
  if not exists (
    select 1
    from public.profiles p
    where p.id = p_actor_id
      and p.active
      and not p.must_change_password
      and p.role in ('admin', 'staff')
  ) then
    raise exception using errcode = 'P0001', message = 'STAFF_AUTH_REQUIRED';
  end if;

  select c.profile_id
  into target_profile_id
  from public.business_customers c
  where c.id = p_customer_id
    and c.profile_id is not null
    and c.account_status in ('active', 'suspended')
    and c.archived_at is null;

  if target_profile_id is null then
    raise exception using errcode = 'P0001', message = 'CUSTOMER_NOT_FOUND';
  end if;

  update public.device_tokens dt
  set
    active = false,
    installation_id_hash = null,
    updated_at = now()
  where dt.profile_id = target_profile_id
    and (dt.active or dt.installation_id_hash is not null);
  get diagnostics changed_rows = row_count;

  insert into public.audit_logs (
    actor_id,
    action,
    entity_table,
    entity_id,
    metadata
  )
  values (
    p_actor_id,
    'customer.device_binding_reset',
    'business_customers',
    p_customer_id,
    jsonb_build_object('deactivated_device_rows', changed_rows)
  );

  return jsonb_build_object(
    'customer_id', p_customer_id,
    'profile_id', target_profile_id,
    'deactivated_device_rows', changed_rows
  );
end;
$$;

revoke all on function public.admin_reset_customer_device_binding(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_reset_customer_device_binding(uuid, uuid)
  to service_role;

-- Tighten storage upload object names: exactly 3 segments and image extension.
drop policy if exists "product images staff insert" on storage.objects;
create policy "product images staff insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and cardinality(storage.foldername(name)) = 3
  and (storage.foldername(name))[1] = 'products'
  and (storage.foldername(name))[2] = auth.uid()::text
  and name !~ '\.\.'
  and name ~ '^products/[0-9a-f-]{36}/[A-Za-z0-9-]+\.(jpg|jpeg|png|webp)$'
);

drop policy if exists "banner images admin insert" on storage.objects;
create policy "banner images admin insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.is_admin()
  and cardinality(storage.foldername(name)) = 3
  and (storage.foldername(name))[1] = 'banners'
  and (storage.foldername(name))[2] = auth.uid()::text
  and name !~ '\.\.'
  and name ~ '^banners/[0-9a-f-]{36}/[A-Za-z0-9-]+\.(jpg|jpeg|png|webp)$'
);

drop policy if exists "logo images admin insert" on storage.objects;
create policy "logo images admin insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.is_admin()
  and cardinality(storage.foldername(name)) = 3
  and (storage.foldername(name))[1] = 'logos'
  and (storage.foldername(name))[2] = auth.uid()::text
  and name !~ '\.\.'
  and name ~ '^logos/[0-9a-f-]{36}/[A-Za-z0-9-]+\.(jpg|jpeg|png|webp)$'
);

drop policy if exists "category icons staff insert" on storage.objects;
create policy "category icons staff insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and cardinality(storage.foldername(name)) = 3
  and (storage.foldername(name))[1] = 'category-icons'
  and (storage.foldername(name))[2] = auth.uid()::text
  and name !~ '\.\.'
  and name ~ '^category-icons/[0-9a-f-]{36}/[A-Za-z0-9-]+\.(jpg|jpeg|png|webp)$'
);

notify pgrst, 'reload schema';
