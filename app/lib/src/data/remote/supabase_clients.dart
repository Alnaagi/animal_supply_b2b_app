import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';

SupabaseClient? get supabaseClient {
  if (!AppConfig.hasSupabase) return null;
  return Supabase.instance.client;
}

// Service role access must stay in Supabase Edge Functions only.
