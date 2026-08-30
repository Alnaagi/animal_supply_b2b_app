import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';
import '../updates/update_link.dart';
import 'app_config.dart';
import 'shop_branding_cache.dart';

class ShopBranding {
  const ShopBranding({
    required this.shopName,
    this.logoUrl,
  });

  final String shopName;
  final String? logoUrl;

  factory ShopBranding.fromSettings(AppSettingsData? settings) {
    final name = settings?.shopName.trim() ?? '';
    final rawLogo = settings?.shopLogoUrl.trim() ?? '';
    return ShopBranding(
      shopName: name.isNotEmpty ? name : AppConfig.shopName,
      logoUrl: rawLogo.isEmpty ? null : safeHttpsUpdateUri(rawLogo)?.toString(),
    );
  }
}

Future<Uint8List?> fetchShopLogoBytes(String? logoUrl) async {
  if (logoUrl == null || logoUrl.trim().isEmpty) return null;
  final uri = safeHttpsUpdateUri(logoUrl.trim());
  if (uri == null) return null;
  try {
    final byteData = await NetworkAssetBundle(uri).load('');
    final bytes = byteData.buffer.asUint8List();
    return bytes.isNotEmpty ? bytes : null;
  } catch (_) {
    return null;
  }
}

final shopBrandingProvider = Provider<ShopBranding>(
  (ref) => ShopBrandingCache.resolve(
    ref.watch(appSettingsProvider).value,
  ),
);

