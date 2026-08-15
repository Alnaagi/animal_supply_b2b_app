alter table public.business_customers
  add column if not exists phone_is_whatsapp boolean not null default true;

comment on column public.business_customers.phone_is_whatsapp is
  'When true, the stored customer phone is the preferred WhatsApp contact number.';
