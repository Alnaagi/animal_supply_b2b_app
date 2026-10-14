import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';

SupabaseClient? get supabaseClient {
  if (!AppConfig.hasSupabase || AppConfig.isDemoMode) return null;
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

// Service role access must stay in Supabase Edge Functions only.
