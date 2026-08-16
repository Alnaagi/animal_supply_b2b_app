import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser_picked_image.dart';

Future<BrowserPickedImage?> pickBrowserProductImageImpl({
  required int maxBytes,
}) async {
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = 'image/jpeg,image/png,image/webp,.jpg,.jpeg,.png,.webp';
  web.document.body?.append(input);

  final selected = Completer<web.File?>();
  void finish(web.File? file) {
    if (!selected.isCompleted) selected.complete(file);
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      finish(input.files?.item(0));
    }.toJS,
  );
  input.addEventListener(
    'cancel',
    (web.Event _) {
      finish(null);
    }.toJS,
  );

  input.click();
  final file = await selected.future;
  input.remove();
  if (file == null) return null;

  if (file.size > maxBytes) {
    throw const BrowserPickedImageException(
      code: 'FILE_TOO_LARGE',
      message: 'حجم الصورة أكبر من 5 MiB.',
    );
  }

  final bytes = await _readBlobBytes(file);
  if (bytes.isEmpty) {
    throw const BrowserPickedImageException(
      code: 'EMPTY_FILE',
      message: 'ملف الصورة فارغ.',
    );
  }
  return BrowserPickedImage(fileName: file.name, bytes: bytes);
}

Future<Uint8List> _readBlobBytes(web.Blob blob) {
  final reader = web.FileReader();
  final done = Completer<Uint8List>();
  reader.addEventListener(
    'loadend',
    (web.Event _) {
      if (done.isCompleted) return;
      final buffer = reader.result;
      if (buffer == null) {
        done.completeError(
          const BrowserPickedImageException(
            code: 'UPLOAD_BROWSER_FILE',
            message:
                'تعذر قراءة ملف الصورة في المتصفح. اختر الصورة مرة أخرى ثم أعد الرفع.',
          ),
        );
        return;
      }
      done.complete((buffer as JSArrayBuffer).toDart.asUint8List());
    }.toJS,
  );
  reader.addEventListener(
    'error',
    (web.Event _) {
      if (done.isCompleted) return;
      done.completeError(
        const BrowserPickedImageException(
          code: 'UPLOAD_BROWSER_FILE',
          message:
              'تعذر قراءة ملف الصورة في المتصفح. اختر الصورة مرة أخرى ثم أعد الرفع.',
        ),
      );
    }.toJS,
  );
  reader.readAsArrayBuffer(blob);
  return done.future;
}
