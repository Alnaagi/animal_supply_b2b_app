import 'shop_document_title_stub.dart'
    if (dart.library.js_interop) 'shop_document_title_web.dart' as platform;

/// localStorage key shared with `web/index.html` and `web/pwa_install.js`.
const shopDocumentTitleStorageKey = 'shop_branding.v1.name';

void applyShopDocumentTitle(String shopName) {
  platform.applyShopDocumentTitleImpl(shopName);
}

String? readCachedShopDocumentTitle() {
  return platform.readCachedShopDocumentTitleImpl();
}
