-- Soft-archive support for admin banner management.
-- Customers only see active, non-archived banners.
-- Hard delete remains available to admins via existing "banners admin manage" policy.

begin;

alter table public.banners
  add column if not exists archived_at timestamptz;

create index if not exists banners_archived_at_idx
  on public.banners (archived_at)
  where archived_at is not null;

create index if not exists banners_active_sort_idx
  on public.banners (sort_order, created_at)
  where active and archived_at is null;

drop policy if exists "banners readable" on public.banners;
create policy "banners readable"
on public.banners
for select
using (
  public.is_active_actor()
  and (
    (active and archived_at is null)
    or public.is_staff_or_admin()
  )
);

commit;
