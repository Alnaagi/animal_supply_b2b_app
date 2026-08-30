import 'package:flutter/material.dart';

import '../../core/widgets/shop_skeleton.dart';

class AuthBootstrapScreen extends StatelessWidget {
  const AuthBootstrapScreen({this.destination, super.key});

  final String? destination;

  @override
  Widget build(BuildContext context) {
    final target = (destination != null && destination!.trim().isNotEmpty)
        ? destination!.trim()
        : WidgetsBinding.instance.platformDispatcher.defaultRouteName;

    final normalized = target.startsWith('/') ? target : '/$target';

    if (normalized.startsWith('/admin')) {
      final sub = normalized.split('?').first;
      final bodySkeleton = switch (sub) {
        '/admin/banners' => const ShopBannersSkeleton(),
        '/admin/products' => const ShopProductListSkeleton(itemCount: 5),
        '/admin/orders' => const ShopOrderListSkeleton(itemCount: 4),
        '/admin/customers' => const ShopCustomerListSkeleton(itemCount: 5),
        '/admin/reports' => const ShopReportsSkeleton(),
        '/admin/settings' => const ShopSettingsSkeleton(),
        '/admin/archive' => const ShopArchiveSkeleton(),
        '/admin/notifications' => const ShopNotificationsSkeleton(),
        '/admin/storefront' || '/admin/storefront/preview' =>
          const ShopStorefrontBuilderSkeleton(),
        _ => const ShopDashboardSkeleton(),
      };
      return ShopAdminShellSkeleton(contentSkeleton: bodySkeleton);
    }

    if (normalized == '/login' ||
        normalized == '/invite' ||
        normalized == '/') {
      return const ShopAuthShellSkeleton();
    }

    final sub = normalized.split('?').first;
    final customerBody = switch (sub) {
      '/catalog' => const Column(
          children: [
            ShopCategoryStripSkeleton(height: 70),
            Expanded(
              child: ShopProductGridSkeleton(itemCount: 6),
            ),
          ],
        ),
      '/cart' || '/checkout' => const ShopCartSkeleton(),
      '/orders' => const ShopOrderListSkeleton(itemCount: 4),
      '/profile' || '/support' => const ShopSettingsSkeleton(),
      _ => sub.startsWith('/product/')
          ? const ShopProductDetailsSkeleton()
          : const ShopCustomerHomeSkeleton(),
    };

    return ShopCustomerShellSkeleton(contentSkeleton: customerBody);
  }
}
