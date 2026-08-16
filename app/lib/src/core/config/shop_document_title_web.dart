import 'package:web/web.dart' as web;

const _storageKey = 'shop_branding.v1.name';

void applyShopDocumentTitleImpl(String shopName) {
  final trimmed = shopName.trim();
  if (trimmed.isEmpty) return;
  web.document.title = trimmed;
  final appleTitle = web.document.querySelector(
    'meta[name="apple-mobile-web-app-title"]',
  );
  appleTitle?.setAttribute('content', trimmed);
  try {
    web.window.localStorage.setItem(_storageKey, trimmed);
  } catch (_) {}
}

String? readCachedShopDocumentTitleImpl() {
  try {
    final value = web.window.localStorage.getItem(_storageKey);
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  } catch (_) {
    return null;
  }
}
