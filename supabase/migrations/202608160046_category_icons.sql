-- Category icons: stable preset key and/or public HTTPS image URL.
-- Uploads reuse the public product-images bucket under
-- category-icons/{auth.uid()}/{file}. Flutter uses the signed-in anon client.

alter table public.categories
  add column if not exists icon_key text,
  add column if not exists icon_url text;

update public.categories
set icon_key = case name
  when 'قطط' then 'cat'
  when 'كلاب' then 'dog'
  when 'طيور' then 'bird'
  when 'أسماك' then 'fish'
  when 'مواشي' then 'livestock'
  when 'مستلزمات' then 'supplies'
  when 'تنظيف' then 'cleaning'
  when 'مكملات' then 'supplements'
  else coalesce(nullif(trim(icon_key), ''), 'category')
end
where coalesce(nullif(trim(icon_key), ''), '') = ''
  and coalesce(nullif(trim(icon_url), ''), '') = '';

alter table public.categories
  drop constraint if exists categories_icon_required;

alter table public.categories
  add constraint categories_icon_required
  check (
    (icon_key is not null and length(trim(icon_key)) > 0)
    or (icon_url is not null and length(trim(icon_url)) > 0)
  );

drop policy if exists "category icons staff insert" on storage.objects;
create policy "category icons staff insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and (storage.foldername(name))[1] = 'category-icons'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists "category icons staff update" on storage.objects;
create policy "category icons staff update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and (storage.foldername(name))[1] = 'category-icons'
  and (
    public.current_role() = 'admin'
    or (storage.foldername(name))[2] = auth.uid()::text
  )
)
with check (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and (storage.foldername(name))[1] = 'category-icons'
  and (
    public.current_role() = 'admin'
    or (storage.foldername(name))[2] = auth.uid()::text
  )
);

drop policy if exists "category icons staff delete" on storage.objects;
create policy "category icons staff delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and (storage.foldername(name))[1] = 'category-icons'
  and (
    public.current_role() = 'admin'
    or (storage.foldername(name))[2] = auth.uid()::text
  )
);

notify pgrst, 'reload schema';
