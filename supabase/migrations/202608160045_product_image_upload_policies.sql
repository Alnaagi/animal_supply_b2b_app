-- Product catalog uploads from Flutter use the signed-in anon client
-- (products/{auth.uid()}/{file}). INSERT must not require owner_id: Storage
-- assigns owner after WITH CHECK, which 403s otherwise. Recreate the bucket
-- contract and grants so current_role() is callable from storage RLS.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'product-images',
  'product-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

grant execute on function public.current_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_staff_or_admin() to authenticated;

drop policy if exists "product images staff insert" on storage.objects;
create policy "product images staff insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and (storage.foldername(name))[1] = 'products'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists "product images staff update" on storage.objects;
create policy "product images staff update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and (storage.foldername(name))[1] = 'products'
  and (
    public.current_role() = 'admin'
    or (storage.foldername(name))[2] = auth.uid()::text
  )
)
with check (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and (storage.foldername(name))[1] = 'products'
  and (
    public.current_role() = 'admin'
    or (storage.foldername(name))[2] = auth.uid()::text
  )
);

drop policy if exists "product images staff delete" on storage.objects;
create policy "product images staff delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and (storage.foldername(name))[1] = 'products'
  and (
    public.current_role() = 'admin'
    or (storage.foldername(name))[2] = auth.uid()::text
  )
);

-- Banner/logo INSERT also failed when owner_id was required before Storage
-- populated it. Keep folder + admin checks; retain owner_id on update/delete.
drop policy if exists "banner images admin insert" on storage.objects;
create policy "banner images admin insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.is_admin()
  and (storage.foldername(name))[1] = 'banners'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists "logo images admin insert" on storage.objects;
create policy "logo images admin insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.is_admin()
  and (storage.foldername(name))[1] = 'logos'
  and (storage.foldername(name))[2] = auth.uid()::text
);

notify pgrst, 'reload schema';
