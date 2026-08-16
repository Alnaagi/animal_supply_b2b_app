import 'browser_file_download_stub.dart'
    if (dart.library.js_interop) 'browser_file_download_web.dart' as platform;

void downloadBytesInBrowser({
  required String filename,
  required List<int> bytes,
  required String mimeType,
}) {
  platform.downloadBytesInBrowserImpl(
    filename: filename,
    bytes: bytes,
    mimeType: mimeType,
  );
}
