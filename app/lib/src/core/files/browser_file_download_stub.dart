void downloadBytesInBrowserImpl({
  required String filename,
  required List<int> bytes,
  required String mimeType,
}) {
  throw UnsupportedError(
    'File download is available in the Flutter web build.',
  );
}
