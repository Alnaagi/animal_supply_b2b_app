import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

class WhatsAppSupport {
  const WhatsAppSupport._();

  static bool get isConfigured => AppConfig.hasSupportWhatsapp;

  static String get displayPhone => AppConfig.supportWhatsapp.trim();

  static String digitsFor(String? phone) =>
      (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  static bool isConfiguredFor(String? phone) {
    final digits = digitsFor(phone);
    return digits.length >= 8 && digits.length <= 15;
  }

  static String displayPhoneFor(String? phone) => (phone ?? '').trim();

  static Future<bool> openMessage(
    String message, {
    String? phone,
  }) async {
    final selectedPhone =
        isConfiguredFor(phone) ? phone : AppConfig.supportWhatsapp;
    if (!isConfiguredFor(selectedPhone)) return false;
    final uri = Uri.https(
      'wa.me',
      digitsFor(selectedPhone),
      <String, String>{'text': message},
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
