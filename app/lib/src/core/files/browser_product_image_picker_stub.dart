import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'browser_picked_image.dart';

Future<BrowserPickedImage?> pickBrowserProductImageImpl({
  required int maxBytes,
}) async {
  const types = XTypeGroup(
    label: 'صور المنتجات',
    extensions: ['jpg', 'jpeg', 'png', 'webp'],
    mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
    uniformTypeIdentifiers: [
      'public.jpeg',
      'public.png',
      'org.webmproject.webp',
    ],
  );
  final file = await openFile(
    acceptedTypeGroups: const [types],
    confirmButtonText: 'اختيار الصورة',
  );
  if (file == null) return null;
  // Read once via XFile bytes. Do not HTTP-fetch file.path (blob: URLs).
  final bytes = Uint8List.fromList(await file.readAsBytes());
  if (bytes.isEmpty) {
    throw const BrowserPickedImageException(
      code: 'EMPTY_FILE',
      message: 'ملف الصورة فارغ.',
    );
  }
  if (bytes.length > maxBytes) {
    throw const BrowserPickedImageException(
      code: 'FILE_TOO_LARGE',
      message: 'حجم الصورة أكبر من 5 MiB.',
    );
  }
  return BrowserPickedImage(fileName: file.name, bytes: bytes);
}
