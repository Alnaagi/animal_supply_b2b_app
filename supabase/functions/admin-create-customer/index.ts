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
  if (!caller || !['admin', 'staff'].includes(caller.role)) {
    return new Response('Forbidden', { status: 403 });
  }

  const body = await req.json();
  const temporaryPassword = `Temp-${crypto.randomUUID().slice(0, 8)}!`;
  const username = body.username ?? body.email ?? body.phone;
  const email = body.email ?? `${username}@example.invalid`;

  const created = await adminClient.auth.admin.createUser({
    email,
    phone: body.phone,
    password: temporaryPassword,
    email_confirm: true,
    phone_confirm: Boolean(body.phone),
    user_metadata: { username },
  });
  if (created.error) return Response.json({ error: created.error.message }, { status: 400 });

  const userId = created.data.user.id;
  await adminClient.from('profiles').insert({
    id: userId,
    username,
    full_name: body.contact_person,
    phone: body.phone,
    role: 'customer',
    must_change_password: true,
  });
  const customer = await adminClient.from('business_customers').insert({
    profile_id: userId,
    business_name: body.business_name,
    contact_person: body.contact_person,
    phone: body.phone,
    city: body.city,
    area: body.area,
    address: body.address,
    price_group_id: body.price_group_id,
  }).select().single();

  const token = crypto.randomUUID();
  const tokenHash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  const hashHex = [...new Uint8Array(tokenHash)].map((b) => b.toString(16).padStart(2, '0')).join('');
  await adminClient.from('invite_tokens').insert({
    customer_id: customer.data.id,
    token_hash: hashHex,
    client_code: username,
    expires_at: new Date(Date.now() + 1000 * 60 * 60 * 24 * 7).toISOString(),
  });

  const downloadLink = body.download_link ?? 'https://example.com/animal-supply.apk';
  const inviteLink = `animalsupplyb2b://invite?token=${token}&client=${encodeURIComponent(username)}`;
  const whatsappMessage = `مرحباً ${body.business_name} 👋
تم إنشاء حسابكم في تطبيق ${body.shop_name ?? 'متجر أعلاف ومستلزمات الحيوانات'} لطلب أعلاف ومستلزمات الحيوانات بالجملة.

بيانات الدخول:
اسم المستخدم: ${username}
كلمة المرور المؤقتة: ${temporaryPassword}

رابط تحميل التطبيق:
${downloadLink}

رابط تفعيل الحساب:
${inviteLink}

ملاحظة: حفاظاً على أمان حسابكم، يرجى تغيير كلمة المرور بعد أول تسجيل دخول.`;

  return Response.json({ customer: customer.data, username, temporaryPassword, inviteLink, whatsappMessage });
});
