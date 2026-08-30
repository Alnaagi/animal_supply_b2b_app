import 'shop_document_title_stub.dart'
    if (dart.library.js_interop) 'shop_document_title_web.dart' as platform;

/// localStorage keys shared with `web/index.html` and `web/pwa_install.js`.
const shopDocumentTitleStorageKey = 'shop_branding.v1.name';
const shopLogoStorageKey = 'shop_branding.v1.logo';

void applyShopDocumentTitle(String shopName) {
  platform.applyShopWebBrandingImpl(shopName, null);
}

void applyShopWebBranding(String shopName, String? logoUrl) {
  platform.applyShopWebBrandingImpl(shopName, logoUrl);
}

String? readCachedShopDocumentTitle() {
  return platform.readCachedShopDocumentTitleImpl();
}

String? readCachedShopLogo() {
  return platform.readCachedShopLogoImpl();
}

