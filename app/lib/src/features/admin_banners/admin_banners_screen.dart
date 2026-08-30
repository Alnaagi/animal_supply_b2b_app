import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/concurrency/stale_write.dart';
import '../../core/config/app_config.dart';
import '../../core/config/shop_branding.dart';
import '../../core/refresh/screen_reload.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/banner_image_crop_dialog.dart';
import '../../core/widgets/circular_upload_progress.dart';
import '../../core/widgets/shop_skeleton.dart';
import '../../core/widgets/shop_refresh_indicator.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/product_images_repository.dart';
import '../admin_dashboard/admin_shell.dart';
import '../customer_home/offer_banner_carousel.dart';

int nextBannerSortOrder(Iterable<AppBanner> banners) {
  var maxOrder = -1;
  for (final banner in banners) {
    if (banner.sortOrder > maxOrder) {
      maxOrder = banner.sortOrder;
    }
  }
  return maxOrder < 0 ? 0 : maxOrder + 1;
}

List<AppBanner> bannersInShowingOrder(Iterable<AppBanner> banners) {
  final sorted = List<AppBanner>.of(banners)
    ..sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  return List<AppBanner>.unmodifiable(sorted);
}

List<AppBanner> activeBannersInShowingOrder(Iterable<AppBanner> banners) {
  return bannersInShowingOrder(
    banners.where((banner) => banner.active && !banner.isArchived),
  );
}

List<AppBanner> moveBannerInShowingOrder(
  Iterable<AppBanner> banners, {
  required String bannerId,
  required int direction,
}) {
  final sorted = List<AppBanner>.from(bannersInShowingOrder(banners));
  final index = sorted.indexWhere((item) => item.id == bannerId);
  final nextIndex = index + direction;
  if (index < 0 || nextIndex < 0 || nextIndex >= sorted.length) {
    return List<AppBanner>.unmodifiable(sorted);
  }
  final moved = sorted.removeAt(index);
  sorted.insert(nextIndex, moved);
  return List<AppBanner>.unmodifiable([
    for (var i = 0; i < sorted.length; i++)
      sorted[i].copyWith(sortOrder: i + 1),
  ]);
}

int? parseBannerSortOrder(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final value = int.tryParse(trimmed);
  if (value == null || value < 0 || value > 100000) return null;
  return value;
}

class AdminBannersScreen extends ConsumerStatefulWidget {
  const AdminBannersScreen({super.key});

  @override
  ConsumerState<AdminBannersScreen> createState() => _AdminBannersScreenState();
}

class _AdminBannersScreenState extends ConsumerState<AdminBannersScreen> {
  late Future<void> _loadFuture;
  List<AppBanner> _allBanners = const [];
  final Set<String> _busyBannerIds = {};
  final Map<String, String> _resolvedProductNames = {};
  _BannerFilter _filter = _BannerFilter.all;

  static const ctaPresets = <String>[
    'عرض',
    'تسوق الآن',
    'اطلب الآن',
    'تصفح العروض',
    'شاهد التفاصيل',
  ];

  @override
  void initState() {
    super.initState();
    _loadFuture = _reloadData();
  }

  Future<List<AppBanner>> _loadBanners() {
    return ref.read(adminRepositoryProvider).allBanners();
  }

  Future<void> _reloadData() async {
    final banners = await _loadBanners();
    final catalog = ref.read(catalogRepositoryProvider);
    final productIds = banners
        .where((item) =>
            item.targetType == 'product' && item.targetValue.isNotEmpty)
        .map((item) => item.targetValue)
        .toSet();
    final names = <String, String>{};
    for (final productId in productIds) {
      try {
        final product = await catalog.productById(productId);
        if (product != null) {
          names[productId] = product.nameAr;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _allBanners = bannersInShowingOrder(banners);
      _resolvedProductNames
        ..clear()
        ..addAll(names);
    });
  }

  Future<void> _reload() async {
    final future = _reloadData();
    setState(() => _loadFuture = future);
    try {
      await future;
    } catch (_) {
      // FutureBuilder shows load error.
    }
  }

  @override
  Widget build(BuildContext context) {
    listenForScreenReload(ref, _reload);
    return AdminShell(
      title: 'إدارة البانرات',
      actions: [
        IconButton(
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث البانرات',
        ),
        IconButton(
          onPressed: () => _showBannerForm(),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          tooltip: 'بانر جديد',
        ),
      ],
      child: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ShopSkeleton(
              semanticLabel: 'جارٍ تحميل العروض الترويجية...',
              child: ShopBannersSkeleton(),
            );
          }
          if (snapshot.hasError) {
            return _BannerLoadError(onRetry: _reload);
          }
          final allBanners = _allBanners;
          final banners = _filteredBanners();
          final managedBanners = allBanners
              .where((item) => !item.isArchived)
              .toList(growable: false);
          final activeCount =
              managedBanners.where((item) => item.active).length;
          final archivedCount =
              allBanners.where((item) => item.isArchived).length;
          final canReorder = _filter == _BannerFilter.all;

          return ShopRefreshIndicator(
            onRefresh: _reload,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView(
                key: const Key('admin-banners-scroll'),
                primary: true,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (AppConfig.isDemoMode) ...[
                    const _DemoBannerNotice(),
                    const SizedBox(height: 12),
                  ],
                  _AdminBannersToolbar(
                    totalCount: managedBanners.length,
                    activeCount: activeCount,
                    archivedCount: archivedCount,
                    filter: _filter,
                    onFilterChanged: (filter) =>
                        setState(() => _filter = filter),
                    onNewBanner: () => _showBannerForm(),
                    onPreviewStore: () => _openStorePreview(),
                  ),
                  const SizedBox(height: 12),
                  if (!canReorder) _ReorderDisabledHint(filter: _filter),
                  const SizedBox(height: 10),
                  if (banners.isEmpty)
                    const _EmptyBanners()
                  else
                    ReorderableListView.builder(
                      key: const ValueKey('admin-banners-reorder-list'),
                      buildDefaultDragHandles: false,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: banners.length,
                      proxyDecorator: (child, index, animation) => Material(
                        elevation: 8,
                        color: Colors.transparent,
                        child: child,
                      ),
                      onReorder: canReorder ? _onReorder : (_, __) {},
                      itemBuilder: (context, index) {
                        final banner = banners[index];
                        return Padding(
                          key: ValueKey('banner-card-${banner.id}'),
                          padding: EdgeInsets.only(
                              bottom: index == banners.length - 1 ? 0 : 8),
                          child: _BannerCard(
                            banner: banner,
                            itemIndex: index,
                            busy: _busyBannerIds.contains(banner.id),
                            reorderEnabled: canReorder,
                            destinationLabel: _resolvedDestinationLabel(banner),
                            onQuickPreview: () =>
                                _openStorePreview(focusBanner: banner),
                            onEdit: () => _showBannerForm(banner),
                            onToggleActive: (value) =>
                                _toggleActive(banner, value),
                            onDuplicate: () => _duplicateBanner(banner),
                            onArchive: banner.isArchived
                                ? null
                                : () => _archiveBanner(banner),
                            onRestore: banner.isArchived
                                ? () => _restoreBanner(banner)
                                : null,
                            onDelete: () => _deleteBanner(banner),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<AppBanner> _filteredBanners() {
    return _allBanners.where((banner) {
      return switch (_filter) {
        _BannerFilter.all => !banner.isArchived,
        _BannerFilter.active => !banner.isArchived && banner.active,
        _BannerFilter.inactive => !banner.isArchived && !banner.active,
        _BannerFilter.archived => banner.isArchived,
      };
    }).toList(growable: false);
  }

  String _resolvedDestinationLabel(AppBanner banner) {
    switch (banner.targetType) {
      case 'product':
        final productName = _resolvedProductNames[banner.targetValue];
        if (productName != null && productName.isNotEmpty) return productName;
        return 'منتج محدد';
      case 'category':
        return banner.targetValue.isEmpty ? 'تصنيف' : banner.targetValue;
      default:
        return 'الكتالوج';
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (_filter != _BannerFilter.all) return;
    HapticFeedback.mediumImpact();
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final current = List<AppBanner>.from(_allBanners);
    final moved = current.removeAt(oldIndex);
    current.insert(newIndex, moved);
    final reordered = [
      for (var i = 0; i < current.length; i++)
        current[i].copyWith(sortOrder: i + 1),
    ];
    setState(() {
      _allBanners = reordered;
    });
    try {
      final repo = ref.read(adminRepositoryProvider);
      for (final next in reordered) {
        final previous = _allBanners.firstWhere((item) => item.id == next.id);
        if (previous.sortOrder != next.sortOrder) {
          await repo.saveBanner(next);
        }
      }
    } catch (_) {
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الترتيب الجديد.')),
      );
    }
  }

  Future<void> _showBannerForm([AppBanner? banner]) async {
    final existing = _allBanners;
    if (!mounted) return;

    final nextSortOrder = nextBannerSortOrder(existing);

    final saved = await showDialog<AppBanner>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _BannerEditorDialog(
        banner: banner,
        nextSortOrder: nextSortOrder,
        ctaPresets: ctaPresets,
      ),
    );

    if (saved == null || !mounted) return;
    await reloadAfterMutation(this, _reloadData);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppConfig.isDemoMode
              ? 'تم حفظ البانر تجريبياً لهذه الجلسة فقط.'
              : 'تم حفظ البانر.',
        ),
      ),
    );
  }

  Future<void> _toggleActive(
    AppBanner banner,
    bool nextActive, {
    bool showUndo = true,
  }) async {
    if (_busyBannerIds.contains(banner.id)) return;
    final before = banner;
    final after = banner.copyWith(active: nextActive);
    setState(() => _busyBannerIds.add(banner.id));
    _replaceBannerLocally(after);
    try {
      await ref
          .read(adminRepositoryProvider)
          .setBannerActive(banner, active: nextActive);
      if (!mounted) return;
      if (showUndo) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextActive
                ? 'تم إظهار البانر للعملاء.'
                : 'تم إيقاف البانر للعملاء.'),
            action: SnackBarAction(
              label: 'تراجع',
              onPressed: () =>
                  unawaited(_toggleActive(after, !nextActive, showUndo: false)),
            ),
          ),
        );
      }
    } catch (error) {
      _replaceBannerLocally(before);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mutationFailureMessageAr(
              error,
              fallback: 'تعذر تغيير حالة البانر. تم التراجع عن التعديل.',
            ),
          ),
        ),
      );
      if (error is StaleWriteException) {
        await reloadAfterMutation(this, _reloadData);
      }
    } finally {
      if (mounted) {
        setState(() => _busyBannerIds.remove(banner.id));
      }
    }
  }

  void _replaceBannerLocally(AppBanner next) {
    setState(() {
      _allBanners = [
        for (final item in _allBanners)
          if (item.id == next.id) next else item,
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    });
  }

  Future<void> _duplicateBanner(AppBanner banner) async {
    if (_busyBannerIds.contains(banner.id)) return;
    setState(() => _busyBannerIds.add(banner.id));
    try {
      final copy = await ref.read(adminRepositoryProvider).saveBanner(
            banner.copyWith(
              id: 'new',
              title: 'نسخة من ${banner.title}',
              active: false,
              sortOrder: nextBannerSortOrder(_allBanners),
            ),
          );
      if (!mounted) return;
      await _reloadData();
      if (!mounted) return;
      await _showBannerForm(copy);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mutationFailureMessageAr(
              error,
              fallback: 'تعذر نسخ البانر حالياً.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyBannerIds.remove(banner.id));
    }
  }

  Future<void> _archiveBanner(AppBanner banner) async {
    if (_busyBannerIds.contains(banner.id) || banner.isArchived) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد أرشفة البانر'),
        content: Text(
          'سيتم إخفاء «${banner.title}» من قائمة الإدارة الافتراضية ومن عرض العملاء. يمكنك استعادته لاحقاً من المؤرشفة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const ValueKey('confirm-archive-banner-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final before = banner;
    final after = banner.copyWith(
      active: false,
      archivedAt: DateTime.now(),
    );
    setState(() => _busyBannerIds.add(banner.id));
    _replaceBannerLocally(after);
    try {
      await ref.read(adminRepositoryProvider).archiveBanner(banner);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت أرشفة البانر.')),
      );
    } catch (error) {
      _replaceBannerLocally(before);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mutationFailureMessageAr(
              error,
              fallback: 'تعذر أرشفة البانر. تم التراجع عن التعديل.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyBannerIds.remove(banner.id));
    }
  }

  Future<void> _restoreBanner(AppBanner banner) async {
    if (_busyBannerIds.contains(banner.id) || !banner.isArchived) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد استعادة البانر'),
        content: Text(
          'ستُعاد «${banner.title}» إلى قائمة الإدارة كبانر متوقف. فعّله يدوياً ليظهر للعملاء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const ValueKey('confirm-restore-banner-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final before = banner;
    final after = banner.copyWith(active: false, clearArchivedAt: true);
    setState(() => _busyBannerIds.add(banner.id));
    _replaceBannerLocally(after);
    try {
      await ref.read(adminRepositoryProvider).restoreBanner(banner);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت استعادة البانر. ما زال متوقفاً حتى تفعيله.'),
        ),
      );
    } catch (error) {
      _replaceBannerLocally(before);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mutationFailureMessageAr(
              error,
              fallback: 'تعذر استعادة البانر. تم التراجع عن التعديل.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyBannerIds.remove(banner.id));
    }
  }

  Future<void> _deleteBanner(AppBanner banner) async {
    if (_busyBannerIds.contains(banner.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف النهائي'),
        content: Text(
          'سيتم حذف «${banner.title}» نهائياً ولا يمكن التراجع عن ذلك. '
          'يُفضّل الأرشفة إن أردت الإبقاء على البانر.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-banner-button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final beforeList = List<AppBanner>.from(_allBanners);
    setState(() {
      _busyBannerIds.add(banner.id);
      _allBanners = [
        for (final item in _allBanners)
          if (item.id != banner.id) item,
      ];
    });
    try {
      await ref.read(adminRepositoryProvider).deleteBanner(banner);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف البانر نهائياً.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _allBanners = beforeList);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mutationFailureMessageAr(
              error,
              fallback: 'تعذر حذف البانر. تم التراجع عن التعديل.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyBannerIds.remove(banner.id));
    }
  }

  Future<void> _openStorePreview({AppBanner? focusBanner}) async {
    final isMobile = MediaQuery.sizeOf(context).width < 800;
    final child = _StorePreviewPanel(
      banners: _allBanners,
      focusBanner: focusBanner,
    );
    if (isMobile) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: 0.95,
          child: child,
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(width: 980, height: 640, child: child),
      ),
    );
  }
}

class _BannerEditorDialog extends ConsumerStatefulWidget {
  const _BannerEditorDialog({
    required this.banner,
    required this.nextSortOrder,
    required this.ctaPresets,
  });

  final AppBanner? banner;
  final int nextSortOrder;
  final List<String> ctaPresets;

  @override
  ConsumerState<_BannerEditorDialog> createState() =>
      _BannerEditorDialogState();
}

class _BannerEditorDialogState extends ConsumerState<_BannerEditorDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController body;
  late final TextEditingController cta;
  late final TextEditingController imageUrl;
  late final TextEditingController productSearch;

  late String targetType;
  late bool active;
  late bool customCta;
  late int sortOrder;
  String? selectedCategory;
  String? selectedProductId;
  String? selectedProductLabel;
  String? saveError;
  String? uploadError;
  Uint8List? imagePreviewBytes;
  double? uploadProgress;
  Timer? uploadProgressTicker;
  bool saving = false;
  bool uploading = false;
  bool loadingLookups = true;
  List<String> categories = const [];
  List<Product> productResults = const [];
  Timer? productSearchDebounce;
  _BannerPreviewMode _previewMode = _BannerPreviewMode.mobile;
  BannerAspectMode aspectMode = BannerAspectMode.wide;
  bool _showAdvancedImageUrl = true;

  bool get editing => widget.banner != null;

  @override
  void initState() {
    super.initState();
    final banner = widget.banner;
    final initialTarget = banner?.targetType.trim().toLowerCase() ?? 'catalog';
    final legacyUrl = initialTarget == 'url';
    targetType =
        legacyUrl || !AppBanner.supportedTargetTypes.contains(initialTarget)
            ? 'catalog'
            : initialTarget;
    title = TextEditingController(text: banner?.title ?? '');
    body = TextEditingController(text: banner?.body ?? '');
    final initialCta = banner?.ctaText.trim().isNotEmpty == true
        ? banner!.ctaText.trim()
        : 'عرض';
    customCta = !widget.ctaPresets.contains(initialCta);
    cta = TextEditingController(text: initialCta);
    imageUrl = TextEditingController(text: banner?.imageUrl ?? '');
    productSearch = TextEditingController();
    active = banner?.active ?? true;
    aspectMode = banner?.aspectMode ?? BannerAspectMode.wide;
    sortOrder = editing ? banner!.sortOrder : widget.nextSortOrder;
    selectedCategory =
        targetType == 'category' && !legacyUrl ? banner?.targetValue : null;
    selectedProductId =
        targetType == 'product' && !legacyUrl ? banner?.targetValue : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadLookups());
    });
  }

  @override
  void dispose() {
    productSearchDebounce?.cancel();
    uploadProgressTicker?.cancel();
    title.dispose();
    body.dispose();
    cta.dispose();
    imageUrl.dispose();
    productSearch.dispose();
    super.dispose();
  }

  void _stopUploadProgressTicker() {
    uploadProgressTicker?.cancel();
    uploadProgressTicker = null;
  }

  void _startUploadProgressTicker({double from = 0.12}) {
    _stopUploadProgressTicker();
    var current = from.clamp(0.0, 0.88);
    uploadProgressTicker =
        Timer.periodic(const Duration(milliseconds: 140), (_) {
      if (!mounted || !uploading) {
        _stopUploadProgressTicker();
        return;
      }
      current = (current + 0.035).clamp(0.0, 0.88);
      setState(() => uploadProgress = current);
    });
  }

  Future<void> _loadLookups() async {
    final catalog = ref.read(catalogRepositoryProvider);
    try {
      final loadedCategories = await catalog.categories();
      String? productLabel = selectedProductId;
      if (selectedProductId != null && selectedProductId!.isNotEmpty) {
        final product = await catalog.productById(selectedProductId!);
        if (product != null) {
          productLabel = product.nameAr;
        }
      }
      if (!mounted) return;
      setState(() {
        categories = _withSelectedCategory(loadedCategories, selectedCategory);
        selectedProductLabel = productLabel;
        loadingLookups = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loadingLookups = false);
    }
  }

  List<String> _withSelectedCategory(
    List<String> options,
    String? selected,
  ) {
    final value = selected?.trim() ?? '';
    if (value.isEmpty || options.contains(value)) {
      return List<String>.unmodifiable(options);
    }
    return List<String>.unmodifiable([value, ...options]);
  }

  void _scheduleProductSearch(String query) {
    productSearchDebounce?.cancel();
    productSearchDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_searchProducts(query));
    });
  }

  Future<void> _searchProducts(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (mounted) setState(() => productResults = const []);
      return;
    }
    try {
      final results = await ref.read(catalogRepositoryProvider).products(
            query: trimmed,
            includeInactive: true,
          );
      if (!mounted) return;
      setState(() => productResults = results.take(12).toList(growable: false));
    } catch (_) {
      if (!mounted) return;
      setState(() => productResults = const []);
    }
  }

  Future<void> _uploadImage() async {
    setState(() {
      uploadError = null;
      saveError = null;
    });
    try {
      final images = ref.read(productImagesRepositoryProvider);
      final picked = await images.pick();
      if (!mounted) return;
      if (picked == null) return;

      final cropped = await showBannerImageCropDialog(
        context,
        imageBytes: picked.bytes,
        sourceFileName: picked.fileName,
        aspectRatio: aspectMode.ratio,
      );
      if (!mounted) return;
      if (cropped == null) return;

      setState(() {
        imagePreviewBytes = cropped.bytes;
        uploading = true;
        uploadProgress = 0.05;
      });
      _startUploadProgressTicker(from: 0.12);

      final result = await images.uploadPicked(
        PickedProductImage(
          fileName: cropped.fileName,
          bytes: cropped.bytes,
        ),
        folder: ProductImagesRepository.bannersFolder,
        onProgress: (fraction) {
          if (!mounted) return;
          if (fraction == null) return;
          if (fraction >= 1) {
            _stopUploadProgressTicker();
            setState(() => uploadProgress = 1);
            return;
          }
          setState(() {
            uploadProgress = fraction.clamp(0.0, 0.95);
          });
        },
      );
      if (!mounted) return;
      _stopUploadProgressTicker();
      setState(() {
        imageUrl.text = result.publicUrl;
        uploading = false;
        uploadProgress = 1;
      });
      formKey.currentState?.validate();
    } on ProductImageUploadException catch (error) {
      if (!mounted) return;
      _stopUploadProgressTicker();
      setState(() {
        uploading = false;
        uploadProgress = null;
        uploadError = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      _stopUploadProgressTicker();
      setState(() {
        uploading = false;
        uploadProgress = null;
        uploadError = mapProductImageUploadError(
          error,
          folder: ProductImagesRepository.bannersFolder,
        ).message;
      });
    }
  }

  Future<void> _save() async {
    if (saving || formKey.currentState?.validate() != true) return;
    setState(() {
      saving = true;
      saveError = null;
    });
    final draft = AppBanner(
      id: widget.banner?.id ?? 'new',
      title: title.text,
      body: body.text,
      ctaText: cta.text,
      imageUrl: imageUrl.text,
      targetType: targetType,
      targetValue: switch (targetType) {
        'category' => selectedCategory ?? '',
        'product' => selectedProductId ?? '',
        _ => '',
      },
      sortOrder: sortOrder,
      active: active,
      aspectMode: aspectMode,
      updatedAt: widget.banner?.updatedAt,
    );
    try {
      final result = await ref.read(adminRepositoryProvider).saveBanner(draft);
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        saving = false;
        saveError = mutationFailureMessageAr(
          error,
          fallback:
              'تعذر حفظ البانر. تحقق من البيانات والصلاحيات والاتصال ثم أعد المحاولة.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1000;
    return AlertDialog(
      title: Text(editing ? 'تعديل البانر' : 'بانر جديد'),
      content: SizedBox(
        width: isDesktop ? 980 : 760,
        child: Form(
          key: formKey,
          child: isDesktop
              ? Row(
                  children: [
                    Expanded(child: _editorForm()),
                    const SizedBox(width: 16),
                    Expanded(child: _editorPreviewCard()),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _editorForm(),
                      const SizedBox(height: 12),
                      _editorPreviewCard(),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: saving ? null : _save,
          icon: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(saving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
    );
  }

  Widget _editorForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (AppConfig.isDemoMode) ...[
            const _DialogDemoNotice(),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: title,
            enabled: !saving,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'العنوان *'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'اكتب عنوان البانر'
                : null,
          ),
          TextFormField(
            controller: body,
            enabled: !saving,
            maxLength: 500,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'الوصف المختصر'),
          ),
          const SizedBox(height: 12),
          Text(
            'نسبة إطار البانر',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<BannerAspectMode>(
            key: const ValueKey('banner-aspect-mode'),
            segments: const [
              ButtonSegment(
                value: BannerAspectMode.wide,
                label: Text('عريض'),
                icon: Icon(Icons.crop_landscape_outlined, size: 18),
              ),
              ButtonSegment(
                value: BannerAspectMode.square,
                label: Text('مربع 1:1'),
                icon: Icon(Icons.crop_square_outlined, size: 18),
              ),
            ],
            selected: {aspectMode},
            onSelectionChanged: saving || uploading
                ? null
                : (selection) => setState(() => aspectMode = selection.single),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            key: const ValueKey('banner-upload-advice'),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: .06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .14),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${aspectMode.uploadAdviceAr}\n'
                'املأ الإطار بالكامل (بدون فراغ أسفل الصورة). '
                'قصّ الصورة بعد الاختيار حسب النسبة المحددة.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('banner-image-upload-button'),
                  onPressed: saving ||
                          uploading ||
                          !ref.read(productImagesRepositoryProvider).canUpload
                      ? null
                      : _uploadImage,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(uploading
                      ? uploadProgressLabelAr(uploadProgress)
                      : 'رفع صورة البانر'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: aspectMode.ratio,
                  child: imagePreviewBytes != null
                      ? Image.memory(
                          imagePreviewBytes!,
                          key: const ValueKey('banner-image-preview'),
                          fit: BoxFit.fill,
                          width: double.infinity,
                          height: double.infinity,
                        )
                      : _BannerUrlThumbnail(url: imageUrl.text),
                ),
              ),
              if (uploading)
                CircularUploadProgress(
                  key: const ValueKey('banner-image-upload-progress'),
                  progress: uploadProgress,
                  size: 64,
                  borderRadius: 16,
                  strokeWidth: 3,
                ),
            ],
          ),
          if (AppConfig.isDemoMode ||
              !ref.read(productImagesRepositoryProvider).canUpload) ...[
            const SizedBox(height: 6),
            Text(
              AppConfig.isDemoMode
                  ? 'رفع الصور غير متاح في الوضع التجريبي. استخدم رابط HTTPS آمناً.'
                  : 'رفع الصور يحتاج ربط Supabase الإنتاجي وتسجيل دخول إداري. استخدم رابط HTTPS يدوياً حالياً.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
          if (uploadError != null) ...[
            const SizedBox(height: 8),
            Text(
              uploadError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextButton.icon(
            key: const ValueKey('banner-image-advanced-toggle'),
            onPressed: () => setState(
              () => _showAdvancedImageUrl = !_showAdvancedImageUrl,
            ),
            icon: Icon(
              _showAdvancedImageUrl ? Icons.expand_less : Icons.expand_more,
            ),
            label: const Text('خيارات متقدمة للصورة (رابط HTTPS)'),
          ),
          Offstage(
            offstage: !_showAdvancedImageUrl,
            child: TextFormField(
              key: const ValueKey('banner-image-url-field'),
              controller: imageUrl,
              enabled: !saving && !uploading,
              maxLength: 2000,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(() => imagePreviewBytes = null),
              decoration: const InputDecoration(
                labelText: 'رابط الصورة HTTPS',
                hintText: 'https://cdn.example.com/banner.webp',
              ),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) return 'أضف رابط صورة أو ارفع صورة';
                return _isSafeHttpsUrl(trimmed)
                    ? null
                    : 'استخدم رابط صورة HTTPS صالحاً ومن دون بيانات دخول';
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildCtaSection(),
          const SizedBox(height: 12),
          _buildDestinationSection(),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: active,
            onChanged:
                saving ? null : (value) => setState(() => active = value),
            title: const Text('ظاهر للعملاء'),
          ),
          if (saveError != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                saveError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCtaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'نص زر الإجراء *',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in widget.ctaPresets)
              ChoiceChip(
                label: Text(preset),
                selected: !customCta && cta.text.trim() == preset,
                onSelected: saving
                    ? null
                    : (_) {
                        setState(() {
                          customCta = false;
                          cta.text = preset;
                        });
                      },
              ),
            ChoiceChip(
              key: const ValueKey('banner-cta-custom-chip'),
              label: const Text('مخصص'),
              selected: customCta,
              onSelected:
                  saving ? null : (_) => setState(() => customCta = true),
            ),
          ],
        ),
        if (customCta) ...[
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('banner-cta-custom-field'),
            controller: cta,
            enabled: !saving,
            maxLength: 40,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'نص الزر المخصص *'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'اكتب نص زر الإجراء'
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildDestinationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('وجهة البانر'),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          key: const ValueKey('banner-target-type-field'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'catalog', label: Text('جميع المنتجات')),
            ButtonSegment(value: 'category', label: Text('تصنيف')),
            ButtonSegment(value: 'product', label: Text('منتج')),
          ],
          selected: {targetType},
          onSelectionChanged: saving
              ? null
              : (selection) => setState(() {
                    targetType = selection.single;
                    if (targetType == 'catalog') {
                      selectedCategory = null;
                      selectedProductId = null;
                      selectedProductLabel = null;
                    }
                  }),
        ),
        if (targetType == 'category') ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selectedCategory,
            decoration: const InputDecoration(labelText: 'اسم التصنيف *'),
            items: [
              for (final category in categories)
                DropdownMenuItem(value: category, child: Text(category)),
            ],
            onChanged: saving
                ? null
                : (value) => setState(() => selectedCategory = value),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'اختر تصنيفاً' : null,
          ),
        ],
        if (targetType == 'product') ...[
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('banner-product-search-field'),
            controller: productSearch,
            enabled: !saving,
            decoration: const InputDecoration(
              labelText: 'ابحث عن منتج',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _scheduleProductSearch,
            validator: (_) =>
                selectedProductId == null ? 'اختر منتجاً من القائمة' : null,
          ),
          if (productResults.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                itemCount: productResults.length,
                itemBuilder: (context, index) {
                  final product = productResults[index];
                  return ListTile(
                    leading: _ProductThumb(url: product.imageUrl),
                    title: Text(product.nameAr),
                    subtitle: Text(product.brand),
                    onTap: () => setState(() {
                      selectedProductId = product.id;
                      selectedProductLabel = product.nameAr;
                      productResults = const [];
                      productSearch.clear();
                    }),
                  );
                },
              ),
            ),
          if (selectedProductLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Chip(label: Text('🎯 $selectedProductLabel')),
            ),
        ],
      ],
    );
  }

  Widget _editorPreviewCard() {
    final banner = AppBanner(
      id: widget.banner?.id ?? 'preview',
      title: title.text.trim().isEmpty ? 'عنوان البانر' : title.text.trim(),
      body: body.text.trim(),
      ctaText: cta.text.trim().isEmpty ? 'عرض' : cta.text.trim(),
      imageUrl: imageUrl.text.trim().isEmpty
          ? 'https://cdn.example.com/banner.webp'
          : imageUrl.text.trim(),
      targetType: targetType,
      targetValue: '',
      sortOrder: sortOrder,
      active: true,
      aspectMode: aspectMode,
    );
    final slides = HomeBannerSlide.fromAdminBanners([banner]);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('معاينة مباشرة'),
                SegmentedButton<_BannerPreviewMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: _BannerPreviewMode.mobile, label: Text('جوال')),
                    ButtonSegment(
                        value: _BannerPreviewMode.desktop,
                        label: Text('حاسوب')),
                  ],
                  selected: {_previewMode},
                  onSelectionChanged: (selection) =>
                      setState(() => _previewMode = selection.single),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _CustomerBannerPreviewStage(
              mobile: _previewMode == _BannerPreviewMode.mobile,
              child: OfferBannerCarousel(
                banners: slides,
                preview: true,
                compact: _previewMode == _BannerPreviewMode.mobile,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BannerFilter { all, active, inactive, archived }

class _AdminBannersToolbar extends StatelessWidget {
  const _AdminBannersToolbar({
    required this.totalCount,
    required this.activeCount,
    required this.archivedCount,
    required this.filter,
    required this.onFilterChanged,
    required this.onPreviewStore,
    required this.onNewBanner,
  });

  final int totalCount;
  final int activeCount;
  final int archivedCount;
  final _BannerFilter filter;
  final ValueChanged<_BannerFilter> onFilterChanged;
  final VoidCallback onPreviewStore;
  final VoidCallback onNewBanner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$totalCount بانرات'),
          Text('$activeCount نشطة'),
          if (archivedCount > 0) Text('$archivedCount مؤرشفة'),
          SegmentedButton<_BannerFilter>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _BannerFilter.all, label: Text('الكل')),
              ButtonSegment(value: _BannerFilter.active, label: Text('النشطة')),
              ButtonSegment(
                  value: _BannerFilter.inactive, label: Text('المتوقفة')),
              ButtonSegment(
                  value: _BannerFilter.archived, label: Text('المؤرشفة')),
            ],
            selected: {filter},
            onSelectionChanged: (selection) =>
                onFilterChanged(selection.single),
          ),
          OutlinedButton.icon(
            key: const ValueKey('preview-store-button'),
            onPressed: onPreviewStore,
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('معاينة المتجر'),
          ),
          FilledButton.icon(
            onPressed: onNewBanner,
            icon: const Icon(Icons.add),
            label: const Text('بانر جديد'),
          ),
        ],
      ),
    );
  }
}

enum _BannerPreviewMode { desktop, mobile }

class _StorePreviewPanel extends ConsumerStatefulWidget {
  const _StorePreviewPanel({required this.banners, this.focusBanner});

  final List<AppBanner> banners;
  final AppBanner? focusBanner;

  @override
  ConsumerState<_StorePreviewPanel> createState() => _StorePreviewPanelState();
}

class _StorePreviewPanelState extends ConsumerState<_StorePreviewPanel> {
  _BannerPreviewMode _mode = _BannerPreviewMode.desktop;
  bool _showAllContext = false;

  @override
  Widget build(BuildContext context) {
    final allActive = activeBannersInShowingOrder(widget.banners);
    final active = widget.focusBanner != null && !_showAllContext
        ? [widget.focusBanner!]
        : allActive;
    final slides = HomeBannerSlide.fromAdminBanners(active);
    final desktop = _mode == _BannerPreviewMode.desktop;
    return DecoratedBox(
      key: const Key('admin-banner-preview-panel'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: .06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  'معاينة المتجر',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                SegmentedButton<_BannerPreviewMode>(
                  key: const Key('admin-banner-preview-mode'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: _BannerPreviewMode.desktop,
                      label: Text('حاسوب'),
                    ),
                    ButtonSegment(
                      value: _BannerPreviewMode.mobile,
                      label: Text('جوال'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) {
                    setState(() => _mode = selection.single);
                  },
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              slides.isEmpty
                  ? 'لا توجد بانرات نشطة في ${ref.watch(shopBrandingProvider).shopName}.'
                  : 'عدد البانرات النشطة: ${allActive.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .78),
                  ),
            ),
            if (widget.focusBanner != null) ...[
              const SizedBox(height: 6),
              CheckboxListTile(
                value: _showAllContext,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('عرض ضمن جميع البانرات'),
                onChanged: (value) =>
                    setState(() => _showAllContext = value ?? false),
              ),
            ],
            if (slides.isNotEmpty) ...[
              const SizedBox(height: 10),
              _CustomerBannerPreviewStage(
                mobile: !desktop,
                child: OfferBannerCarousel(
                  key: const Key('admin-banner-client-carousel'),
                  banners: slides,
                  preview: true,
                  compact: !desktop,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Desktop uses nearly the full card width. Mobile is a centered phone-width
/// stage with a hairline frame — not a thick black bezel.
class _CustomerBannerPreviewStage extends StatelessWidget {
  const _CustomerBannerPreviewStage({
    required this.mobile,
    required this.child,
  });

  final bool mobile;
  final Widget child;

  static const double _mobileWidth = 360;

  @override
  Widget build(BuildContext context) {
    final stage = DecoratedBox(
      key: const Key('admin-banner-client-preview-stage'),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(mobile ? 20 : 18),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .primary
              .withValues(alpha: mobile ? .18 : .10),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: .06),
            blurRadius: mobile ? 10 : 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, 10, 10, mobile ? 8 : 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            if (mobile) ...[
              const SizedBox(height: 8),
              Center(
                child: DecoratedBox(
                  key: const Key('admin-banner-preview-home-indicator'),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: .42),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const SizedBox(width: 92, height: 4),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!mobile) {
      return KeyedSubtree(
        key: const Key('admin-banner-client-preview-desktop'),
        child: stage,
      );
    }

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        key: const Key('admin-banner-client-preview-phone'),
        constraints: const BoxConstraints(maxWidth: _mobileWidth),
        child: stage,
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.banner,
    required this.itemIndex,
    required this.busy,
    required this.reorderEnabled,
    required this.destinationLabel,
    required this.onQuickPreview,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDuplicate,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
  });

  final AppBanner banner;
  final int itemIndex;
  final bool busy;
  final bool reorderEnabled;
  final String destinationLabel;
  final VoidCallback onQuickPreview;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onDuplicate;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            key: ValueKey('banner-thumbnail-${banner.id}'),
            onTap: onQuickPreview,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: AspectRatio(
              aspectRatio: isMobile ? 16 / 7 : 16 / 5,
              child: Image.network(
                banner.imageUrl,
                fit: BoxFit.fill,
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: const Center(
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        banner.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                    if (reorderEnabled)
                      Tooltip(
                        message: 'اسحب لتغيير الترتيب',
                        child: ReorderableDragStartListener(
                          index: itemIndex,
                          enabled: !busy,
                          child: const Icon(Icons.drag_indicator),
                        ),
                      ),
                  ],
                ),
                if (banner.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    banner.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(
                        active: banner.active, archived: banner.isArchived),
                    _DestinationChip(
                        type: banner.targetType, value: destinationLabel),
                  ],
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: banner.active && !banner.isArchived,
                  onChanged: busy || banner.isArchived ? null : onToggleActive,
                  title: Text(
                    banner.isArchived
                        ? 'مؤرشف (غير ظاهر للعملاء)'
                        : 'ظاهر للعملاء',
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: busy ? null : onQuickPreview,
                      child: const Text('معاينة'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : onEdit,
                      child: const Text('تعديل'),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'preview') onQuickPreview();
                        if (value == 'edit') onEdit();
                        if (value == 'duplicate') onDuplicate();
                        if (value == 'toggle') onToggleActive(!banner.active);
                        if (value == 'archive' && onArchive != null) {
                          onArchive!();
                        }
                        if (value == 'restore' && onRestore != null) {
                          onRestore!();
                        }
                        if (value == 'delete' && onDelete != null) onDelete!();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                            value: 'preview', child: Text('معاينة')),
                        const PopupMenuItem(
                            value: 'edit', child: Text('تعديل')),
                        if (!banner.isArchived)
                          const PopupMenuItem(
                              value: 'duplicate', child: Text('نسخ البانر')),
                        if (!banner.isArchived)
                          PopupMenuItem(
                              value: 'toggle',
                              child: Text(banner.active ? 'إيقاف' : 'تفعيل')),
                        if (onArchive != null)
                          const PopupMenuItem(
                              value: 'archive', child: Text('أرشفة')),
                        if (onRestore != null)
                          const PopupMenuItem(
                              value: 'restore', child: Text('استعادة')),
                        if (onDelete != null)
                          const PopupMenuItem(
                              value: 'delete', child: Text('حذف نهائي')),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerSortOrderField extends StatefulWidget {
  const _BannerSortOrderField({
    required this.bannerId,
    required this.sortOrder,
    required this.enabled,
    required this.onSubmit,
  });

  final String bannerId;
  final int sortOrder;
  final bool enabled;
  final ValueChanged<int> onSubmit;

  @override
  State<_BannerSortOrderField> createState() => _BannerSortOrderFieldState();
}

class _BannerSortOrderFieldState extends State<_BannerSortOrderField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.sortOrder}');
  }

  @override
  void didUpdateWidget(covariant _BannerSortOrderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sortOrder != widget.sortOrder &&
        _controller.text.trim() != '${widget.sortOrder}') {
      _controller.text = '${widget.sortOrder}';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _emit() {
    final parsed = parseBannerSortOrder(_controller.text);
    if (parsed == null || parsed == widget.sortOrder) return;
    widget.onSubmit(parsed);
  }

  void _scheduleEmit(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _emit);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'الترتيب',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) _emit();
            },
            child: TextField(
              key: ValueKey('banner-sort-order-${widget.bannerId}'),
              controller: _controller,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
              onChanged: _scheduleEmit,
              onSubmitted: (_) => _emit(),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active, this.archived = false});

  final bool active;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final label = archived ? '📦 مؤرشف' : (active ? '🟢 نشط' : '⚪ متوقف');
    return Chip(
      label: Text(label),
      backgroundColor: archived
          ? Colors.blueGrey.withValues(alpha: .12)
          : active
              ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: .10)
              : Colors.grey.withValues(alpha: .12),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DestinationChip extends StatelessWidget {
  const _DestinationChip({required this.type, required this.value});

  final String type;
  final String value;

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      'product' => '🎯 منتج',
      'category' => '📂 تصنيف',
      _ => '🛒 الكتالوج',
    };
    return Chip(
      label: Text('$label · $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (!_isSafeHttpsUrl(url)) {
      return const CircleAvatar(child: Icon(Icons.inventory_2_outlined));
    }
    return CircleAvatar(
      backgroundImage: NetworkImage(url!),
      onBackgroundImageError: (_, __) {},
    );
  }
}

class _ReorderDisabledHint extends StatelessWidget {
  const _ReorderDisabledHint({required this.filter});

  final _BannerFilter filter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'إعادة الترتيب متاحة فقط عند اختيار "الكل". الفلتر الحالي: ${switch (filter) {
          _BannerFilter.active => 'النشطة',
          _BannerFilter.inactive => 'المتوقفة',
          _BannerFilter.archived => 'المؤرشفة',
          _ => 'الكل',
        }}',
      ),
    );
  }
}

class _DemoBannerNotice extends StatelessWidget {
  const _DemoBannerNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.orange.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: AppTheme.orange),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'وضع تجريبي: إضافات وتعديلات البانرات محفوظة في ذاكرة هذه الجلسة فقط، ولا تُنشر لعملاء حقيقيين.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerUrlThumbnail extends StatelessWidget {
  const _BannerUrlThumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final trimmed = url.trim();
    if (!_isSafeHttpsUrl(trimmed)) {
      return ColoredBox(
        key: const ValueKey('banner-image-preview-empty'),
        color: Theme.of(context).colorScheme.primaryContainer,
        child: const Center(child: Icon(Icons.image_outlined)),
      );
    }
    return Image.network(
      trimmed,
      key: const ValueKey('banner-image-preview'),
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

class _DialogDemoNotice extends StatelessWidget {
  const _DialogDemoNotice();

  @override
  Widget build(BuildContext context) {
    return Text(
      'حفظ تجريبي للجلسة الحالية فقط.',
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _BannerLoadError extends StatelessWidget {
  const _BannerLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 54),
            const SizedBox(height: 12),
            const Text(
              'تعذر تحميل البانرات',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'تحقق من الاتصال والصلاحيات ثم أعد المحاولة.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBanners extends ConsumerWidget {
  const _EmptyBanners();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopName = ref.watch(shopBrandingProvider).shopName;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_carousel_outlined, size: 54),
            const SizedBox(height: 12),
            const Text(
              'لا توجد بانرات بهذا الفلتر',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text('أنشئ بانراً جديداً لـ $shopName أو غيّر فلتر الحالة.'),
          ],
        ),
      ),
    );
  }
}

bool _isSafeHttpsUrl(String? raw) {
  final uri = Uri.tryParse(raw?.trim() ?? '');
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}
