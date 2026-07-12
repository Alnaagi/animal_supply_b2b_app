import 'package:supabase_flutter/supabase_flutter.dart';

class AppConfig {
  static const shopName = String.fromEnvironment(
    'SHOP_NAME',
    defaultValue: 'متجر أعلاف ومستلزمات الحيوانات',
  );
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const downloadLink = String.fromEnvironment(
    'APP_DOWNLOAD_LINK',
    defaultValue: 'https://example.com/animal-supply.apk',
  );
  static const apkLink = String.fromEnvironment(
    'APK_LINK',
    defaultValue: 'https://example.com/downloads/animal-supply-b2b.apk',
  );
  static const supportWhatsapp = String.fromEnvironment(
    'SUPPORT_WHATSAPP',
    defaultValue: '+218910000000',
  );

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> tryInitializeSupabase() async {
    if (!hasSupabase) return;
    await Supabase.initialize(
        url: supabaseUrl, publishableKey: supabaseAnonKey);
  }
}
