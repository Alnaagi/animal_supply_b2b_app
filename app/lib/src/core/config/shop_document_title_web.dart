import 'package:web/web.dart' as web;

const _nameStorageKey = 'shop_branding.v1.name';
const _logoStorageKey = 'shop_branding.v1.logo';

void applyShopWebBrandingImpl(String shopName, String? logoUrl) {
  final trimmedName = shopName.trim();
  if (trimmedName.isNotEmpty) {
    web.document.title = trimmedName;
    final appleTitle = web.document.querySelector(
      'meta[name="apple-mobile-web-app-title"]',
    );
    appleTitle?.setAttribute('content', trimmedName);
    try {
      web.window.localStorage.setItem(_nameStorageKey, trimmedName);
    } catch (_) {}
  }

  final trimmedLogo = logoUrl?.trim() ?? '';
  if (trimmedLogo.isNotEmpty) {
    final favicons = web.document.querySelectorAll('link[rel*="icon"]');
    if (favicons.length == 0) {
      final link = web.document.createElement('link') as web.HTMLLinkElement;
      link.rel = 'icon';
      link.type = 'image/png';
      link.href = trimmedLogo;
      web.document.head?.appendChild(link);
    } else {
      for (var i = 0; i < favicons.length; i++) {
        final el = favicons.item(i) as web.Element?;
        el?.setAttribute('href', trimmedLogo);
      }
    }

    final appleIcons =
        web.document.querySelectorAll('link[rel="apple-touch-icon"]');
    if (appleIcons.length == 0) {
      final link = web.document.createElement('link') as web.HTMLLinkElement;
      link.rel = 'apple-touch-icon';
      link.href = trimmedLogo;
      web.document.head?.appendChild(link);
    } else {
      for (var i = 0; i < appleIcons.length; i++) {
        final el = appleIcons.item(i) as web.Element?;
        el?.setAttribute('href', trimmedLogo);
      }
    }

    try {
      web.window.localStorage.setItem(_logoStorageKey, trimmedLogo);
    } catch (_) {}
  } else if (logoUrl != null && logoUrl.isEmpty) {
    final favicons = web.document.querySelectorAll('link[rel*="icon"]');
    for (var i = 0; i < favicons.length; i++) {
      final el = favicons.item(i) as web.Element?;
      el?.setAttribute('href', 'favicon.png');
    }
    final appleIcons =
        web.document.querySelectorAll('link[rel="apple-touch-icon"]');
    for (var i = 0; i < appleIcons.length; i++) {
      final el = appleIcons.item(i) as web.Element?;
      el?.setAttribute('href', 'icons/Icon-192.png');
    }
    try {
      web.window.localStorage.removeItem(_logoStorageKey);
    } catch (_) {}
  }
}

String? readCachedShopDocumentTitleImpl() {
  try {
    final value = web.window.localStorage.getItem(_nameStorageKey);
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  } catch (_) {
    return null;
  }
}

String? readCachedShopLogoImpl() {
  try {
    final value = web.window.localStorage.getItem(_logoStorageKey);
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  } catch (_) {
    return null;
  }
}

