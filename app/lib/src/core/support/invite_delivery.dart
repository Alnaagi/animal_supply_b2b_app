Uri inviteWhatsappContactUri(String normalizedPhone) {
  if (!RegExp(r'^[0-9]{8,15}$').hasMatch(normalizedPhone)) {
    throw ArgumentError.value(
      normalizedPhone,
      'normalizedPhone',
      'A normalized international phone number is required.',
    );
  }
  return Uri.https('wa.me', '/$normalizedPhone');
}
