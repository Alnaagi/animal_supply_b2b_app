-- storage.foldername(name) returns directory segments only (excludes the
-- filename). For paths like products/{uid}/{file}.png the array length is 2,
-- not 3. Migration 20260819165500 incorrectly required cardinality = 3, which
-- made every product/banner/logo/category-icon INSERT fail WITH CHECK (403).
-- Keep path hardening (exact 2 folders + owned uid + image extension regex).

drop policy if exists "product images staff insert" on storage.objects;
create policy "product images staff insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and cardinality(storage.foldername(name)) = 2
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
  and cardinality(storage.foldername(name)) = 2
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
  and cardinality(storage.foldername(name)) = 2
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
  and cardinality(storage.foldername(name)) = 2
  and (storage.foldername(name))[1] = 'category-icons'
  and (storage.foldername(name))[2] = auth.uid()::text
  and name !~ '\.\.'
  and name ~ '^category-icons/[0-9a-f-]{36}/[A-Za-z0-9-]+\.(jpg|jpeg|png|webp)$'
);

notify pgrst, 'reload schema';
