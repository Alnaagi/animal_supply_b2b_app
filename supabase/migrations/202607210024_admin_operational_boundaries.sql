-- Match database authorization to the admin-only banner/pricing routes and
-- complete authenticated ownership checks for product-image maintenance.

begin;

drop policy if exists "banners staff manage" on public.banners;
drop policy if exists "banners admin manage" on public.banners;
create policy "banners admin manage"
on public.banners
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "product prices staff manage"
  on public.product_prices;
drop policy if exists "product prices admin manage"
  on public.product_prices;
create policy "product prices admin manage"
on public.product_prices
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "special prices staff manage"
  on public.customer_special_prices;
drop policy if exists "special prices admin manage"
  on public.customer_special_prices;
create policy "special prices admin manage"
on public.customer_special_prices
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "product images staff select" on storage.objects;
create policy "product images staff select"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and (storage.foldername(name))[1] = 'products'
  and (
    public.current_role() = 'admin'
    or (
      (storage.foldername(name))[2] = auth.uid()::text
      and owner_id = auth.uid()::text
    )
  )
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
    or (
      (storage.foldername(name))[2] = auth.uid()::text
      and owner_id = auth.uid()::text
    )
  )
)
with check (
  bucket_id = 'product-images'
  and public.current_role() in ('admin', 'staff')
  and (storage.foldername(name))[1] = 'products'
  and (
    public.current_role() = 'admin'
    or (
      (storage.foldername(name))[2] = auth.uid()::text
      and owner_id = auth.uid()::text
    )
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
    or (
      (storage.foldername(name))[2] = auth.uid()::text
      and owner_id = auth.uid()::text
    )
  )
);

notify pgrst, 'reload schema';

commit;
