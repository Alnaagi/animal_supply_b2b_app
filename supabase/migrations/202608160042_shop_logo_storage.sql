-- Store/app logo lives in the existing public product-images bucket.
-- Writes stay admin-only under logos/{auth.uid()}/{file}, matching banners.
-- shop_name and shop_logo_url are readable without a session so login,
-- download, and the document title can show the live store identity.

insert into public.app_settings (key, value)
values ('shop_logo_url', '')
on conflict (key) do nothing;

drop policy if exists "branding settings public read" on public.app_settings;
create policy "branding settings public read"
on public.app_settings
for select
to anon, authenticated
using (key in ('shop_name', 'shop_logo_url'));

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
  and owner_id = auth.uid()::text
);

drop policy if exists "logo images admin update" on storage.objects;
create policy "logo images admin update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'product-images'
  and public.is_admin()
  and cardinality(storage.foldername(name)) = 2
  and (storage.foldername(name))[1] = 'logos'
  and (storage.foldername(name))[2] = auth.uid()::text
  and owner_id = auth.uid()::text
)
with check (
  bucket_id = 'product-images'
  and public.is_admin()
  and cardinality(storage.foldername(name)) = 2
  and (storage.foldername(name))[1] = 'logos'
  and (storage.foldername(name))[2] = auth.uid()::text
  and owner_id = auth.uid()::text
);

drop policy if exists "logo images admin delete" on storage.objects;
create policy "logo images admin delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'product-images'
  and public.is_admin()
  and cardinality(storage.foldername(name)) = 2
  and (storage.foldername(name))[1] = 'logos'
  and (storage.foldername(name))[2] = auth.uid()::text
  and owner_id = auth.uid()::text
);
