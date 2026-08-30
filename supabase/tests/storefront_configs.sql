-- Storefront configs RLS and RPC authorization smoke tests.
-- Run with: psql ... -f supabase/tests/storefront_configs.sql

begin;

select plan(11);

-- Default config helper
select ok(
  (public.storefront_default_config_v1() ->> 'schemaVersion')::int = 1,
  'default config uses schema v1'
);

select lives_ok(
  $$ select public.validate_storefront_config_v1(public.storefront_default_config_v1()) $$,
  'default config passes validation'
);

-- Duplicate section should fail validation
select throws_ok(
  $$
    select public.validate_storefront_config_v1(
      jsonb_set(
        public.storefront_default_config_v1(),
        '{sections,0,type}',
        '"header"'::jsonb,
        false
      )
    )
  $$,
  'P0001',
  'STOREFRONT_SECTION_DUPLICATE',
  'duplicate section types rejected'
);

-- Invalid color should fail
select throws_ok(
  $$
    select public.validate_storefront_config_v1(
      jsonb_set(
        public.storefront_default_config_v1(),
        '{theme,primaryColor}',
        '"not-a-color"'::jsonb
      )
    )
  $$,
  'P0001',
  'STOREFRONT_COLOR_INVALID',
  'invalid hex colors rejected'
);

-- Seed row exists
select ok(
  exists(select 1 from public.storefront_configs where id = 'default'),
  'singleton storefront row seeded'
);

select ok(
  (select published_config from public.storefront_configs where id = 'default')
    = public.storefront_default_config_v1(),
  'published config matches bundled default'
);

select ok(
  (select draft_config from public.storefront_configs where id = 'default')
    = (select published_config from public.storefront_configs where id = 'default'),
  'draft initially matches published (no surprise live change)'
);

-- Audit action names documented in migration
select ok(
  exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_save_storefront_draft'
  ),
  'admin_save_storefront_draft RPC exists'
);

select ok(
  exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_published_storefront_config'
  ),
  'get_published_storefront_config RPC exists'
);

select ok(
  exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_publish_storefront'
      and pg_get_function_identity_arguments(p.oid) like '%jsonb%'
  ),
  'admin_publish_storefront accepts optional p_draft_config'
);

select ok(
  exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_reset_storefront_draft'
  ),
  'admin_reset_storefront_draft RPC exists'
);

-- Audit insert must not cast singleton text id into uuid entity_id
select lives_ok(
  $$
    insert into public.audit_logs (
      actor_id, action, entity_table, entity_id, metadata
    ) values (
      null,
      'storefront.draft_updated',
      'storefront_configs',
      null,
      jsonb_build_object('configId', 'default')
    )
  $$,
  'storefront audit accepts null entity_id with configId metadata'
);

select * from finish();
rollback;
