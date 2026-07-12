import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const adminClient = createClient(supabaseUrl, serviceRole);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });

  const { data: caller } = await userClient.from('profiles').select('role').single();
  if (!caller) return new Response('Forbidden', { status: 403 });

  const { order_id } = await req.json();
  const order = await adminClient
    .from('orders')
    .select('id, subtotal, business_customers(business_name)')
    .eq('id', order_id)
    .single();
  if (order.error) return Response.json({ error: order.error.message }, { status: 400 });

  const businessName = order.data.business_customers?.business_name ?? 'عميل B2B';
  const title = 'طلب جديد';
  const body = `${businessName} أرسل طلب رقم ${order.data.id} بقيمة ${Number(order.data.subtotal ?? 0).toFixed(2)} د.ل`;
  const payload = { order_id: order.data.id, type: 'new_order' };

  await adminClient.from('notifications').insert({
    recipient_role: 'admin',
    type: 'new_order',
    title,
    body,
    payload,
  });
  await adminClient.from('notifications').insert({
    recipient_role: 'staff',
    type: 'new_order',
    title,
    body,
    payload,
  });

  const tokens = await adminClient
    .from('admin_device_tokens')
    .select('fcm_token')
    .eq('active', true);

  // Production FCM HTTP v1 requires Firebase service account credentials and an OAuth access token.
  // Keep that secret server-side only. This MVP function records notifications now and is the only
  // place where FCM delivery should be added.
  return Response.json({
    ok: true,
    stored: true,
    tokenCount: tokens.data?.length ?? 0,
    fcmDelivery: 'TODO: configure Firebase HTTP v1 credentials in Edge Function secrets',
  });
});
