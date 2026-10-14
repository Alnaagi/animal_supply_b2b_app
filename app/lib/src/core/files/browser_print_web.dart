import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool printHtmlDocumentImpl(String html) {
  if (html.trim().isEmpty) return false;
  final blob = web.Blob(
    [html.toJS].toJS,
    web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final popup = web.window.open(url, '_blank');
  if (popup != null) return true;

  final iframe = web.HTMLIFrameElement()
    ..src = url
    ..setAttribute(
      'style',
      'position:fixed;right:0;bottom:0;width:0;height:0;border:0;',
    );
  web.document.body?.append(iframe);
  iframe.addEventListener(
    'load',
    (web.Event _) {
      iframe.contentWindow?.print();
    }.toJS,
  );
  return true;
}

bool printPdfDocumentImpl({
  required List<int> bytes,
  required String title,
}) {
  if (bytes.isEmpty) return false;
  final payload = Uint8List.fromList(bytes);
  final blob = web.Blob(
    [payload.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final popup = web.window.open(url, '_blank');
  if (popup != null) return true;

  final iframe = web.HTMLIFrameElement()
    ..src = url
    ..setAttribute(
      'style',
      'position:fixed;right:0;bottom:0;width:0;height:0;border:0;',
    );
  web.document.body?.append(iframe);
  iframe.addEventListener(
    'load',
    (web.Event _) {
      iframe.contentWindow?.print();
    }.toJS,
  );
  return true;
}
