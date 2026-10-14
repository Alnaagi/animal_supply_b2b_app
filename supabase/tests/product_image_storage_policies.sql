\set ON_ERROR_STOP on

begin;

do $$
declare
  sample_path text :=
    'products/11111111-2222-4333-8444-555555555555/abc-def.png';
  folders text[];
  policy_check text;
  policy_name text;
begin
  folders := storage.foldername(sample_path);
  if cardinality(folders) <> 2 then
    raise exception
      'storage.foldername must return 2 segments for % (got %)',
      sample_path,
      cardinality(folders);
  end if;

  if storage.filename(sample_path) <> 'abc-def.png' then
    raise exception 'storage.filename mismatch for %', sample_path;
  end if;

  foreach policy_name in array array[
    'product images staff insert',
    'banner images admin insert',
    'logo images admin insert',
    'category icons staff insert'
  ]
  loop
    select lower(coalesce(with_check, ''))
    into policy_check
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = policy_name;

    if policy_check is null then
      raise exception 'missing storage policy: %', policy_name;
    end if;

    if policy_check not like '%cardinality(storage.foldername(name)) = 2%'
      and policy_check not like '%cardinality(foldername(name)) = 2%' then
      raise exception
        'policy % must require foldername cardinality = 2 (got: %)',
        policy_name,
        policy_check;
    end if;

    if policy_check like '%cardinality% = 3%' then
      raise exception
        'policy % still requires foldername cardinality = 3',
        policy_name;
    end if;

    if policy_check not like '%product-images%' then
      raise exception 'policy % must scope to product-images bucket', policy_name;
    end if;

    if policy_check not like '%auth.uid()%' then
      raise exception 'policy % must bind path owner to auth.uid()', policy_name;
    end if;

    if policy_check not like '%!~%' then
      raise exception 'policy % must keep path-traversal guard', policy_name;
    end if;

    if policy_check not like '%(jpg|jpeg|png|webp)%' then
      raise exception 'policy % must keep image-extension path regex', policy_name;
    end if;
  end loop;

  -- Customer/anon must not gain insert policies on product-images objects.
  if exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and cmd in ('ALL', 'INSERT')
      and permissive = 'PERMISSIVE'
      and roles && array['anon'::name, 'public'::name]
      and lower(coalesce(with_check, '') || ' ' || coalesce(qual, ''))
        like '%product-images%'
  ) then
    raise exception 'anon/public must not have product-images write policies';
  end if;
end;
$$;

rollback;
