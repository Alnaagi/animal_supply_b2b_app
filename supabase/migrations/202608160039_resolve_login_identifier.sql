-- Maps a typed username or phone to the Auth email/phone actually stored
-- when the admin created the customer. Login must not guess a domain.
create or replace function public.resolve_login_identifier(p_identifier text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_raw text := lower(trim(coalesce(p_identifier, '')));
  v_email text;
  v_phone text;
  v_digits text;
begin
  if v_raw = '' then
    return '{}'::jsonb;
  end if;

  select u.email, u.phone
    into v_email, v_phone
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(p.username) = v_raw
  limit 1;

  if found then
    return jsonb_strip_nulls(
      jsonb_build_object(
        'email', nullif(v_email, ''),
        'phone', nullif(v_phone, '')
      )
    );
  end if;

  v_digits := regexp_replace(coalesce(p_identifier, ''), '[^0-9]', '', 'g');
  if v_digits <> '' then
    select u.email, u.phone
      into v_email, v_phone
    from public.profiles p
    join auth.users u on u.id = p.id
    where regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') = v_digits
       or regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') = v_digits
    limit 1;
    if found then
      return jsonb_strip_nulls(
        jsonb_build_object(
          'email', nullif(v_email, ''),
          'phone', nullif(v_phone, '')
        )
      );
    end if;
  end if;

  return '{}'::jsonb;
end;
$$;

revoke all on function public.resolve_login_identifier(text)
  from public, anon, authenticated, service_role;
grant execute on function public.resolve_login_identifier(text)
  to anon, authenticated;

comment on function public.resolve_login_identifier(text) is
  'Returns only the Auth email/phone for a username or phone so the login screen can sign in without exposing other account fields.';
