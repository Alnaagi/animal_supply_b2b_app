-- Public product-image delivery with authenticated staff/admin-only writes.
-- Flutter uses the signed-in anon client; no service-role key is required.

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
