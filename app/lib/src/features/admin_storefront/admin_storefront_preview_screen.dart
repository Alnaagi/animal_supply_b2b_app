import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/admin_models.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../customer_home/customer_shell.dart';
import '../storefront/storefront_home_data.dart';
import '../storefront/storefront_home_renderer.dart';
import '../storefront/storefront_theme_scope.dart';
import 'admin_storefront_controller.dart';
import 'widgets/storefront_preview_frame.dart';

class AdminStorefrontPreviewScreen extends ConsumerStatefulWidget {
  const AdminStorefrontPreviewScreen({super.key});

  @override
  ConsumerState<AdminStorefrontPreviewScreen> createState() =>
      _AdminStorefrontPreviewScreenState();
}

class _AdminStorefrontPreviewScreenState
    extends ConsumerState<AdminStorefrontPreviewScreen> {
  @override
  Widget build(BuildContext context) {
    final builder = ref.watch(adminStorefrontControllerProvider);
    final config = builder.activeConfig;

    return Scaffold(
      appBar: AppBar(
        title: const Text('معاينة تصميم المتجر'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.orange.shade100,
            padding: const EdgeInsets.all(12),
            child: const Text(
              'وضع المعاينة — خارج واجهة العميل الفعلية',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: Future.wait([
                ref.read(catalogRepositoryProvider).products(),
                ref.read(adminRepositoryProvider).banners(),
              ]),
              builder: (context, snapshot) {
                final products = snapshot.data != null &&
                        snapshot.data!.isNotEmpty &&
                        snapshot.data![0] is List<Product>
                    ? snapshot.data![0] as List<Product>
                    : const <Product>[];
                final banners =
                    snapshot.data != null && snapshot.data!.length > 1
                        ? snapshot.data![1] as List<AppBanner>
                        : const <AppBanner>[];

                return StorefrontPreviewFrame(
                  device: builder.previewDevice,
                  child: StorefrontThemeScope(
                    config: config,
                    child: CustomerPreviewShell(
                      child: StorefrontHomeRenderer(
                        config: config,
                        data: StorefrontHomeData(
                          products: products,
                          banners: banners,
                          userName: 'معاينة المتجر',
                          userLocation: 'معاينة كاملة',
                        ),
                        interactionMode: StorefrontInteractionMode.preview,
                        renderMode: StorefrontRenderMode.adminPreview,
                        actions: const StorefrontHomeActions(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
