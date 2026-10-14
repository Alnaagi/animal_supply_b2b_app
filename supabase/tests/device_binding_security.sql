\set ON_ERROR_STOP on

begin;

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'device_tokens'
      and column_name = 'installation_id_hash'
  ) then
    raise exception 'installation_id_hash column is missing on public.device_tokens';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.register_device_token_transaction(uuid,text,text,text,text,text,text,text,integer)',
    'EXECUTE'
  ) then
    raise exception 'authenticated unexpectedly executes register_device_token_transaction';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.register_device_token_transaction(uuid,text,text,text,text,text,text,text,integer)',
    'EXECUTE'
  ) then
    raise exception 'service_role cannot execute register_device_token_transaction';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.admin_reset_customer_device_binding(uuid,uuid)',
    'EXECUTE'
  ) then
    raise exception 'authenticated unexpectedly executes admin_reset_customer_device_binding';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.admin_reset_customer_device_binding(uuid,uuid)',
    'EXECUTE'
  ) then
    raise exception 'service_role cannot execute admin_reset_customer_device_binding';
  end if;
end;
$$;

rollback;
