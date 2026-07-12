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

  const { customer_id, client_code } = await req.json();
  const token = crypto.randomUUID();
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  const tokenHash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
  const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 7).toISOString();

  const inserted = await adminClient.from('invite_tokens').insert({
    customer_id,
    token_hash: tokenHash,
    client_code,
    expires_at: expiresAt,
  }).select().single();
  if (inserted.error) return Response.json({ error: inserted.error.message }, { status: 400 });

  return Response.json({
    token,
    inviteLink: `animalsupplyb2b://invite?token=${token}&client=${encodeURIComponent(client_code ?? '')}`,
    expiresAt,
  });
});
