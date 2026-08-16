Uri inviteWhatsappComposeUri({
  String? normalizedPhone,
  required String text,
}) {
  final phone = normalizedPhone?.trim() ?? '';
  if (phone.isNotEmpty && !RegExp(r'^[0-9]{8,15}$').hasMatch(phone)) {
    throw ArgumentError.value(
      normalizedPhone,
      'normalizedPhone',
      'A normalized international phone number is required.',
    );
  }
  return Uri.https(
    'wa.me',
    phone.isEmpty ? '/' : '/$phone',
    <String, String>{'text': text},
  );
}
