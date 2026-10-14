import 'shop_document_title_stub.dart'
    if (dart.library.js_interop) 'shop_document_title_web.dart' as platform;

/// localStorage keys shared with `web/index.html` and `web/pwa_install.js`.
const shopDocumentTitleStorageKey = 'shop_branding.v1.name';
const shopLogoStorageKey = 'shop_branding.v1.logo';
const shopThemeStorageKey = 'storefront_theme.v1';

void applyShopDocumentTitle(String shopName) {
  platform.applyShopWebBrandingImpl(shopName, null);
}

void applyShopWebBranding(String shopName, String? logoUrl) {
  platform.applyShopWebBrandingImpl(shopName, logoUrl);
}

/// Keeps the browser chrome and the install prompt aligned with the currently
/// published storefront palette. The web implementation caches this so the
/// palette is available before Flutter finishes booting on the next visit.
void applyShopWebTheme(Map<String, dynamic> theme) {
  platform.applyShopWebThemeImpl(theme);
}

String? readCachedShopDocumentTitle() {
  return platform.readCachedShopDocumentTitleImpl();
}

String? readCachedShopLogo() {
  return platform.readCachedShopLogoImpl();
}
