import '../auth/login_identifier.dart';
import 'whatsapp_support.dart';

class CustomerContact {
  const CustomerContact._();

  static String? whatsappDigits(String? phone) {
    final libyan = normalizeLibyanLoginPhone(phone ?? '');
    if (libyan != null) return libyan.replaceAll(RegExp(r'[^0-9]'), '');
    if (WhatsAppSupport.isConfiguredFor(phone)) {
      return WhatsAppSupport.digitsFor(phone);
    }
    return null;
  }

  static Uri? whatsappUri({
    required String? phone,
    String text = '',
  }) {
    final digits = whatsappDigits(phone);
    if (digits == null) return null;
    return Uri.https(
      'wa.me',
      '/$digits',
      text.trim().isEmpty ? const <String, String>{} : {'text': text},
    );
  }

  static Uri? telUri(String? phone) {
    final digits = whatsappDigits(phone);
    if (digits == null) return null;
    return Uri.parse('tel:+$digits');
  }
}
