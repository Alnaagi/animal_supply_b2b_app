class BannerDestination {
  const BannerDestination.internal(this.path) : externalUri = null;

  const BannerDestination.external(this.externalUri) : path = '/catalog';

  final String path;
  final Uri? externalUri;

  bool get isExternal => externalUri != null;
}

BannerDestination resolveBannerDestination({
  required String targetType,
  required String targetValue,
}) {
  final value = targetValue.trim();
  switch (targetType) {
    case 'category':
      if (value.isNotEmpty) {
        return BannerDestination.internal(
          '/catalog?category=${Uri.encodeComponent(value)}',
        );
      }
    case 'product':
      if (RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
        return BannerDestination.internal(
          '/product/${Uri.encodeComponent(value)}',
        );
      }
    case 'url':
      final uri = Uri.tryParse(value);
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        return BannerDestination.external(uri);
      }
  }
  return const BannerDestination.internal('/catalog');
}
