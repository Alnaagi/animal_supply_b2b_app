import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/shop_skeleton.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/product.dart';
import '../../data/models/storefront_config.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../../data/repositories/storefront_repository.dart';
import '../admin_dashboard/admin_shell.dart';
import '../customer_home/customer_shell.dart';
import '../storefront/storefront_home_data.dart';
import '../storefront/storefront_home_renderer.dart';
import '../storefront/storefront_theme_scope.dart';
import 'admin_storefront_controller.dart';
import 'storefront_breakpoints.dart';
import 'widgets/storefront_design_panel.dart';
import 'widgets/storefront_inspector_panel.dart';
import 'widgets/storefront_mobile_header.dart';
import 'widgets/storefront_preview_frame.dart';
import 'widgets/storefront_preview_settings_sheet.dart';
import 'widgets/storefront_sections_panel.dart';
import 'widgets/storefront_sidebar.dart';
import 'widgets/storefront_toolbar.dart';

class AdminStorefrontScreen extends ConsumerStatefulWidget {
  const AdminStorefrontScreen({super.key});

  @override
  ConsumerState<AdminStorefrontScreen> createState() =>
      _AdminStorefrontScreenState();
}

class _AdminStorefrontScreenState extends ConsumerState<AdminStorefrontScreen> {
  Future<List<Product>>? _productsFuture;
  Future<List<dynamic>>? _metaFuture;

  @override
  void initState() {
    super.initState();
    _reloadPreviewData();
  }

  void _reloadPreviewData() {
    final catalog = ref.read(catalogRepositoryProvider);
    _productsFuture = catalog.products();
    _metaFuture = Future.wait([
      catalog.productCategories(),
      ref.read(adminRepositoryProvider).banners(),
    ]);
  }

  Future<bool> _confirmDiscard() async {
    final state = ref.read(adminStorefrontControllerProvider);
    if (!state.hasUnsavedChanges) return true;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تغييرات غير محفوظة'),
        content: const Text(
          'ما زالت بعض التعديلات بانتظار الحفظ التلقائي. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('البقاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _confirmPublish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('نشر تصميم المتجر'),
        content: const Text(
          'سيتم تطبيق المسودة الحالية على واجهة العملاء فور النشر. '
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نشر التغييرات'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok =
        await ref.read(adminStorefrontControllerProvider.notifier).publish();
    if (ok) {
      ref.invalidate(publishedStorefrontConfigProvider);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'تم نشر تصميم المتجر.' : 'تعذر نشر التصميم.'),
      ),
    );
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة ضبط التصميم'),
        content: const Text(
          'ستُستعاد المسودة إلى التصميم الافتراضي للمتجر. '
          'لن يُنشر التغيير تلقائياً. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('إعادة ضبط'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok =
        await ref.read(adminStorefrontControllerProvider.notifier).resetDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'تمت استعادة التصميم الافتراضي.' : 'تعذر إعادة الضبط.',
        ),
      ),
    );
  }

  void _showStaleWriteSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'إعادة التحميل',
          onPressed: () {
            ref.read(adminStorefrontControllerProvider.notifier).load();
          },
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  void _previewPublished() {
    ref.read(adminStorefrontControllerProvider.notifier).togglePreviewPublished(
          true,
        );
    ref
        .read(adminStorefrontControllerProvider.notifier)
        .setMobileTab(StorefrontBuilderTab.preview);
  }

  @override
  Widget build(BuildContext context) {
    final builder = ref.watch(adminStorefrontControllerProvider);
    final controller = ref.read(adminStorefrontControllerProvider.notifier);

    ref.listen(adminStorefrontControllerProvider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        if (next.staleWrite) {
          _showStaleWriteSnack(next.errorMessage!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(next.errorMessage!)),
          );
        }
      }
    });

    return PopScope(
      canPop: !builder.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final flushed = await controller.flushAutosave();
        if (!context.mounted) return;
        if (flushed &&
            !ref.read(adminStorefrontControllerProvider).hasUnsavedChanges) {
          Navigator.of(context).maybePop();
          return;
        }
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: AdminShell(
        title: '',
        compactForStorefrontBuilder: true,
        child: builder.loading
            ? const ShopSkeleton(
                semanticLabel: 'جارٍ تجهيز مصمم الواجهة...',
                child: ShopStorefrontBuilderSkeleton(),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Viewport width drives breakpoints; nav rail reduces inner constraints.
                  final width = MediaQuery.sizeOf(context).width;
                  if (StorefrontBreakpoints.isDesktop(width)) {
                    return _DesktopBuilderShell(
                      builder: builder,
                      controller: controller,
                      productsFuture: _productsFuture,
                      metaFuture: _metaFuture,
                      onReload: _reloadPreviewData,
                      onReset: _confirmReset,
                      onPublish: _confirmPublish,
                    );
                  }
                  if (StorefrontBreakpoints.isTablet(width)) {
                    return _TabletBuilderShell(
                      builder: builder,
                      controller: controller,
                      productsFuture: _productsFuture,
                      metaFuture: _metaFuture,
                      onReload: _reloadPreviewData,
                      onReset: _confirmReset,
                      onPublish: _confirmPublish,
                    );
                  }
                  return _MobileBuilderShell(
                    builder: builder,
                    controller: controller,
                    productsFuture: _productsFuture,
                    metaFuture: _metaFuture,
                    onReload: _reloadPreviewData,
                    onReset: _confirmReset,
                    onPublish: _confirmPublish,
                    onPreviewPublished: _previewPublished,
                  );
                },
              ),
      ),
    );
  }
}

class _DesktopBuilderShell extends StatelessWidget {
  const _DesktopBuilderShell({
    required this.builder,
    required this.controller,
    required this.productsFuture,
    required this.metaFuture,
    required this.onReload,
    required this.onReset,
    required this.onPublish,
  });

  final StorefrontBuilderState builder;
  final AdminStorefrontController controller;
  final Future<List<Product>>? productsFuture;
  final Future<List<dynamic>>? metaFuture;
  final VoidCallback onReload;
  final VoidCallback onReset;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StorefrontToolbar(
          state: builder,
          controller: controller,
          onReset: onReset,
          onPublish: onPublish,
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StorefrontSidebar(
                state: builder,
                controller: controller,
                onReset: onReset,
              ),
              Expanded(
                child: _StorefrontPreviewHost(
                  builder: builder,
                  controller: controller,
                  productsFuture: productsFuture,
                  metaFuture: metaFuture,
                  onReload: onReload,
                  compactPreview: false,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: builder.inspectorCollapsed ? 48 : 340,
                child: builder.inspectorCollapsed
                    ? _InspectorCollapseRail(
                        onExpand: controller.toggleInspectorCollapsed,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              tooltip: 'طي المفتش',
                              onPressed: controller.toggleInspectorCollapsed,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ),
                          Expanded(
                            child: StorefrontInspectorPanel(
                              state: builder,
                              controller: controller,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabletBuilderShell extends StatelessWidget {
  const _TabletBuilderShell({
    required this.builder,
    required this.controller,
    required this.productsFuture,
    required this.metaFuture,
    required this.onReload,
    required this.onReset,
    required this.onPublish,
  });

  final StorefrontBuilderState builder;
  final AdminStorefrontController controller;
  final Future<List<Product>>? productsFuture;
  final Future<List<dynamic>>? metaFuture;
  final VoidCallback onReload;
  final VoidCallback onReset;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StorefrontToolbar(
          state: builder,
          controller: controller,
          onReset: onReset,
          onPublish: onPublish,
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StorefrontPreviewHost(
                  builder: builder,
                  controller: controller,
                  productsFuture: productsFuture,
                  metaFuture: metaFuture,
                  onReload: onReload,
                  compactPreview: false,
                ),
              ),
              if (!builder.inspectorCollapsed)
                SizedBox(
                  width: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: 'طي المفتش',
                          onPressed: controller.toggleInspectorCollapsed,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ),
                      Expanded(
                        child: StorefrontInspectorPanel(
                          state: builder,
                          controller: controller,
                        ),
                      ),
                    ],
                  ),
                )
              else
                _InspectorCollapseRail(
                  onExpand: controller.toggleInspectorCollapsed,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileBuilderShell extends StatelessWidget {
  const _MobileBuilderShell({
    required this.builder,
    required this.controller,
    required this.productsFuture,
    required this.metaFuture,
    required this.onReload,
    required this.onReset,
    required this.onPublish,
    required this.onPreviewPublished,
  });

  final StorefrontBuilderState builder;
  final AdminStorefrontController controller;
  final Future<List<Product>>? productsFuture;
  final Future<List<dynamic>>? metaFuture;
  final VoidCallback onReload;
  final VoidCallback onReset;
  final VoidCallback onPublish;
  final VoidCallback onPreviewPublished;

  void _openSectionInspector(BuildContext context, StorefrontSectionType type) {
    controller.selectSection(type);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return StorefrontInspectorPanel(
              state: builder,
              controller: controller,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StorefrontMobileHeader(
          state: builder,
          controller: controller,
          onPublish: onPublish,
          onReset: onReset,
          onPreviewPublished: onPreviewPublished,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 360;
              return SegmentedButton<StorefrontBuilderTab>(
                key: const Key('storefront-mobile-tabs'),
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity:
                      narrow ? VisualDensity.compact : VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: [
                  for (final tab in StorefrontBuilderTab.values)
                    ButtonSegment(
                      value: tab,
                      label: Text(
                        tab.labelAr,
                        style: TextStyle(fontSize: narrow ? 12 : 14),
                      ),
                    ),
                ],
                selected: {builder.mobileTab},
                onSelectionChanged: (value) =>
                    controller.setMobileTab(value.first),
              );
            },
          ),
        ),
        Expanded(
          child: switch (builder.mobileTab) {
            StorefrontBuilderTab.preview => _StorefrontPreviewHost(
                builder: builder,
                controller: controller,
                productsFuture: productsFuture,
                metaFuture: metaFuture,
                onReload: onReload,
                compactPreview: true,
              ),
            StorefrontBuilderTab.sections => StorefrontSectionsPanel(
                config: builder.draft,
                selected: builder.selectedSection,
                compact: true,
                onSelect: (type) => _openSectionInspector(context, type),
                onReorder: controller.reorderSection,
                onVisibilityChanged: controller.setSectionVisible,
              ),
            StorefrontBuilderTab.design => Stack(
                children: [
                  StorefrontDesignPanel(
                    state: builder,
                    controller: controller,
                    onReset: onReset,
                  ),
                  PositionedDirectional(
                    end: 16,
                    bottom: 16,
                    child: FloatingActionButton.extended(
                      key: const Key('storefront-mobile-preview-fab'),
                      onPressed: () => controller.setMobileTab(
                        StorefrontBuilderTab.preview,
                      ),
                      icon: const Text('👁'),
                      label: const Text('معاينة'),
                    ),
                  ),
                ],
              ),
          },
        ),
      ],
    );
  }
}

class _InspectorCollapseRail extends StatelessWidget {
  const _InspectorCollapseRail({required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            IconButton(
              tooltip: 'توسيع المفتش',
              onPressed: onExpand,
              icon: const Icon(Icons.chevron_left),
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

class _StorefrontPreviewHost extends ConsumerWidget {
  const _StorefrontPreviewHost({
    required this.builder,
    required this.controller,
    required this.productsFuture,
    required this.metaFuture,
    required this.onReload,
    required this.compactPreview,
  });

  final StorefrontBuilderState builder;
  final AdminStorefrontController controller;
  final Future<List<Product>>? productsFuture;
  final Future<List<dynamic>>? metaFuture;
  final VoidCallback onReload;
  final bool compactPreview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = builder.activeConfig;
    final previewCustomerId = builder.previewCustomerId;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compactPreview ? 10 : 12,
              compactPreview ? 6 : 8,
              compactPreview ? 10 : 12,
              0,
            ),
            child: compactPreview
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _CompactPreviewSafetyBadge(),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const Key('storefront-preview-settings-button'),
                          onPressed: () => showStorefrontPreviewSettingsSheet(
                            context: context,
                            state: builder,
                            controller: controller,
                          ),
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          label: const Text('⚙ إعدادات المعاينة'),
                        ),
                      ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final compactControls = constraints.maxWidth < 720;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _WidePreviewSafetyBadge(),
                          const SizedBox(height: 6),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: _PreviewDeviceControls(
                              builder: builder,
                              controller: controller,
                              compact: compactControls,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compactPreview ? 6 : 10,
                compactPreview ? 4 : 8,
                compactPreview ? 6 : 10,
                compactPreview ? 6 : 10,
              ),
              child: FutureBuilder<List<dynamic>>(
                future: Future.wait([
                  productsFuture ?? Future.value(<Product>[]),
                  metaFuture ?? Future.value(<dynamic>[]),
                  if (previewCustomerId != null &&
                      builder.pricePreviewMode ==
                          StorefrontPricePreviewMode.customerPreview)
                    ref
                        .read(ordersRepositoryProvider)
                        .ordersForCustomer(previewCustomerId)
                  else
                    Future.value(<dynamic>[]),
                ]),
                builder: (context, snapshot) {
                  final products = snapshot.data != null &&
                          snapshot.data!.isNotEmpty &&
                          snapshot.data![0] is List<Product>
                      ? snapshot.data![0] as List<Product>
                      : const <Product>[];
                  final meta =
                      snapshot.data != null && snapshot.data!.length > 1
                          ? snapshot.data![1]
                          : const <dynamic>[];
                  final categories = meta is List && meta.isNotEmpty
                      ? meta[0] as List
                      : const [];
                  final banners = meta is List && meta.length > 1
                      ? meta[1] as List<AppBanner>
                      : const <AppBanner>[];
                  final orders =
                      snapshot.data != null && snapshot.data!.length > 2
                          ? snapshot.data![2] as List
                          : const [];

                  return SizedBox.expand(
                    child: StorefrontPreviewFrame(
                      device: builder.previewDevice,
                      compact: compactPreview,
                      child: StorefrontThemeScope(
                        config: config,
                        child: CustomerPreviewShell(
                          child: StorefrontHomeRenderer(
                            config: config,
                            data: StorefrontHomeData(
                              products: products,
                              categories: categories.cast(),
                              banners: banners,
                              recentOrders: orders.cast(),
                              userName: 'معاينة',
                              userLocation: 'طرابلس',
                            ),
                            interactionMode: StorefrontInteractionMode.preview,
                            renderMode: StorefrontRenderMode.adminPreview,
                            scrollKey:
                                const Key('admin-storefront-preview-scroll'),
                            priceResolver: builder.pricePreviewMode ==
                                    StorefrontPricePreviewMode.basePrice
                                ? (product) => product.price
                                : null,
                            actions: const StorefrontHomeActions(),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactPreviewSafetyBadge extends StatelessWidget {
  const _CompactPreviewSafetyBadge();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('storefront-preview-mode-badge'),
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('معاينة آمنة'),
              content: const Text(
                'هذه معاينة للتصميم فقط. لا تُنفَّذ إجراءات السلة أو الطلبات '
                'أثناء المعاينة.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسناً'),
                ),
              ],
            ),
          );
        },
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.orange.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: AppTheme.orange.withValues(alpha: .35),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '👁 وضع المعاينة',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: Colors.orange.shade900,
            ),
          ),
        ),
      ),
    );
  }
}

class _WidePreviewSafetyBadge extends StatelessWidget {
  const _WidePreviewSafetyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('storefront-preview-mode-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.orange.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: AppTheme.orange.withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined,
              size: 16, color: Colors.orange.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'وضع المعاينة — لا تُنفَّذ إجراءات السلة أو الطلبات',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewDeviceControls extends StatelessWidget {
  const _PreviewDeviceControls({
    required this.builder,
    required this.controller,
    this.compact = false,
  });

  final StorefrontBuilderState builder;
  final AdminStorefrontController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Wrap(
        spacing: 6,
        children: [
          for (final device in StorefrontPreviewDevice.values)
            IconButton(
              key: Key('storefront-preview-device-${device.name}'),
              tooltip: device.labelAr,
              onPressed: () => controller.setPreviewDevice(device),
              icon: Icon(_deviceIcon(device)),
              color: builder.previewDevice == device
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade600,
            ),
        ],
      );
    }

    return SegmentedButton<StorefrontPreviewDevice>(
      key: const Key('storefront-preview-device-segments'),
      segments: [
        for (final device in StorefrontPreviewDevice.values)
          ButtonSegment(
            value: device,
            icon: Icon(_deviceIcon(device), key: Key('storefront-preview-device-${device.name}')),
            label: Text(device.labelAr),
          ),
      ],
      selected: {builder.previewDevice},
      onSelectionChanged: (value) => controller.setPreviewDevice(value.first),
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  IconData _deviceIcon(StorefrontPreviewDevice device) {
    switch (device) {
      case StorefrontPreviewDevice.phone:
        return Icons.smartphone_outlined;
      case StorefrontPreviewDevice.desktop:
        return Icons.desktop_windows_outlined;
    }
  }
}
