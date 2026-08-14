import 'update_link.dart';

Uri? resolvePublicDownloadPageUri({
  required String configuredDownloadLink,
  required String publicAppOrigin,
  required Uri currentBase,
  required bool isWeb,
}) {
  final configured = safeHttpsUpdateUri(configuredDownloadLink);
  if (configured != null) return configured;

  final origin = safeHttpsUpdateUri(publicAppOrigin);
  if (origin != null) {
    return origin.replace(path: '/download', query: null, fragment: null);
  }

  if (isWeb) {
    final current = safeHttpsUpdateUri(currentBase.toString());
    if (current != null) {
      return current.replace(path: '/download', query: null, fragment: null);
    }
  }
  return null;
}

Uri? resolvePublicWebAppUri({
  required String publicAppOrigin,
  required Uri currentBase,
  required bool isWeb,
}) {
  final origin = safeHttpsUpdateUri(publicAppOrigin);
  if (origin != null) {
    return origin.replace(path: '/', query: null, fragment: null);
  }
  if (!isWeb) return null;
  final current = safeHttpsUpdateUri(currentBase.toString());
  return current?.replace(path: '/', query: null, fragment: null);
}

Uri whatsappDownloadShareUri({
  required Uri downloadPage,
  required String shopName,
}) {
  return Uri.https('wa.me', '/', {
    'text': 'رابط تحميل تطبيق $shopName:\n$downloadPage',
  });
}
