import 'browser_picked_image.dart';
import 'browser_product_image_picker_stub.dart'
    if (dart.library.js_interop) 'browser_product_image_picker_web.dart'
    as platform;

export 'browser_picked_image.dart';

Future<BrowserPickedImage?> pickBrowserProductImage({
  required int maxBytes,
}) =>
    platform.pickBrowserProductImageImpl(maxBytes: maxBytes);
