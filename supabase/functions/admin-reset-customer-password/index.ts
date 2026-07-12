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
  if (!caller || !['admin', 'staff'].includes(caller.role)) return new Response('Forbidden', { status: 403 });

  const { user_id } = await req.json();
  const temporaryPassword = `Temp-${crypto.randomUUID().slice(0, 8)}!`;
  const result = await adminClient.auth.admin.updateUserById(user_id, { password: temporaryPassword });
  if (result.error) return Response.json({ error: result.error.message }, { status: 400 });
  await adminClient.from('profiles').update({ must_change_password: true }).eq('id', user_id);
  return Response.json({ temporaryPassword });
});
