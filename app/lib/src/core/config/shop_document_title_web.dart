import 'dart:convert';

import 'package:web/web.dart' as web;

const _nameStorageKey = 'shop_branding.v1.name';
const _logoStorageKey = 'shop_branding.v1.logo';
const _themeStorageKey = 'storefront_theme.v1';

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

void applyShopWebThemeImpl(Map<String, dynamic> theme) {
  final normalized = <String, String>{
    'primaryColor': _safeHex(theme['primaryColor'], '#146C4E'),
    'secondaryColor': _safeHex(theme['secondaryColor'], '#8A623F'),
    'backgroundColor': _safeHex(theme['backgroundColor'], '#F7F2EA'),
    'cardColor': _safeHex(theme['cardColor'], '#FFFFFF'),
    'textColor': _safeHex(theme['textColor'], '#173F32'),
  };
  final root = web.document.documentElement as web.HTMLElement?;
  if (root != null) {
    final primary = normalized['primaryColor']!;
    final secondary = normalized['secondaryColor']!;
    final background = normalized['backgroundColor']!;
    final card = normalized['cardColor']!;
    final text = normalized['textColor']!;
    root.style
      ..setProperty('--storefront-primary', primary)
      ..setProperty('--storefront-primary-soft', _rgba(primary, .12))
      ..setProperty('--storefront-primary-strong', _rgba(primary, .22))
      ..setProperty('--storefront-secondary', secondary)
      ..setProperty('--storefront-background', background)
      ..setProperty('--storefront-card', card)
      ..setProperty('--storefront-text', text)
      ..setProperty('--storefront-muted', _rgba(text, .72));
  }

  final meta = web.document.querySelector('meta[name="theme-color"]');
  if (meta != null) {
    meta.setAttribute('content', normalized['primaryColor']!);
  } else {
    final created = web.document.createElement('meta');
    created.setAttribute('name', 'theme-color');
    created.setAttribute('content', normalized['primaryColor']!);
    web.document.head?.appendChild(created);
  }

  try {
    web.window.localStorage.setItem(_themeStorageKey, jsonEncode(normalized));
  } catch (_) {}
}

String _safeHex(Object? raw, String fallback) {
  final value = raw?.toString().trim() ?? '';
  return RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)
      ? value.toUpperCase()
      : fallback;
}

String _rgba(String hex, double alpha) {
  final value = int.parse(hex.substring(1), radix: 16);
  final red = (value >> 16) & 0xFF;
  final green = (value >> 8) & 0xFF;
  final blue = value & 0xFF;
  return 'rgba($red, $green, $blue, $alpha)';
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
