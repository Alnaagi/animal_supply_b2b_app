-- Per-banner frame aspect: wide (default landscape hero) or square (1:1).
-- Existing rows default to wide so production layout does not suddenly change.

begin;

alter table public.banners
  add column if not exists aspect_mode text not null default 'wide';

alter table public.banners
  drop constraint if exists banners_aspect_mode_check;

alter table public.banners
  add constraint banners_aspect_mode_check
  check (aspect_mode in ('wide', 'square'));

comment on column public.banners.aspect_mode is
  'Customer banner frame: wide (landscape strip) or square (1:1).';

commit;
