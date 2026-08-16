import 'dart:typed_data';

class BrowserPickedImage {
  const BrowserPickedImage({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

class BrowserPickedImageException implements Exception {
  const BrowserPickedImageException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;
}
