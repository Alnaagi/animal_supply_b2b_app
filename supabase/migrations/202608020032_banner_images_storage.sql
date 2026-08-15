-- Banner management is admin-only in both the app and public.banners RLS.
-- Keep every write under product-images/banners/{auth.uid()}/{file} and
-- require the storage object to remain owned by the signed-in administrator.

drop policy if exists "banner images staff insert" on storage.objects;
drop policy if exists "banner images admin insert" on storage.objects;
create policy "banner images admin insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.is_admin()
  and cardinality(storage.foldername(name)) = 2
  and (storage.foldername(name))[1] = 'banners'
  and (storage.foldername(name))[2] = auth.uid()::text
  and owner_id = auth.uid()::text
);

drop policy if exists "banner images staff update" on storage.objects;
drop policy if exists "banner images admin update" on storage.objects;
create policy "banner images admin update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'product-images'
  and public.is_admin()
  and cardinality(storage.foldername(name)) = 2
  and (storage.foldername(name))[1] = 'banners'
  and (storage.foldername(name))[2] = auth.uid()::text
  and owner_id = auth.uid()::text
)
with check (
  bucket_id = 'product-images'
  and public.is_admin()
  and cardinality(storage.foldername(name)) = 2
  and (storage.foldername(name))[1] = 'banners'
  and (storage.foldername(name))[2] = auth.uid()::text
  and owner_id = auth.uid()::text
);

drop policy if exists "banner images staff delete" on storage.objects;
drop policy if exists "banner images admin delete" on storage.objects;
create policy "banner images admin delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'product-images'
  and public.is_admin()
  and cardinality(storage.foldername(name)) = 2
  and (storage.foldername(name))[1] = 'banners'
  and (storage.foldername(name))[2] = auth.uid()::text
  and owner_id = auth.uid()::text
);
