import 'browser_print_stub.dart'
    if (dart.library.js_interop) 'browser_print_web.dart' as platform;

bool printHtmlDocument(String html) {
  return platform.printHtmlDocumentImpl(html);
}
