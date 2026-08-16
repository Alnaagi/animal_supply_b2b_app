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
import '../../core/widgets/shop_loading.dart';
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
    banners.where((banner) => banner.active),
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
  late Future<List<AppBanner>> _bannersFuture;
  final Set<String> _busyBannerIds = {};
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
    _bannersFuture = _loadBanners();
  }

  Future<List<AppBanner>> _loadBanners() {
    return ref.read(adminRepositoryProvider).allBanners();
  }

  Future<void> _reload() async {
    final future = _loadBanners();
    setState(() => _bannersFuture = future);
    try {
      await future;
    } catch (_) {
      // FutureBuilder shows the load error.
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
      child: FutureBuilder<List<AppBanner>>(
        future: _bannersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ShopLoading.page();
          }
          if (snapshot.hasError) {
            return _BannerLoadError(onRetry: _reload);
          }

          final allBanners = snapshot.data ?? const <AppBanner>[];
          final banners = bannersInShowingOrder(
            allBanners.where(
              (banner) => switch (_filter) {
                _BannerFilter.all => true,
                _BannerFilter.active => banner.active,
                _BannerFilter.inactive => !banner.active,
              },
            ),
          );

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
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
                children: [
                  if (AppConfig.isDemoMode) ...[
                    const _DemoBannerNotice(),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.start,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _showBannerForm(),
                        icon: const Icon(Icons.add),
                        label: const Text('بانر جديد'),
                      ),
                      SegmentedButton<_BannerFilter>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: _BannerFilter.all,
                            label: Text('الكل'),
                          ),
                          ButtonSegment(
                            value: _BannerFilter.active,
                            label: Text('النشطة'),
                          ),
                          ButtonSegment(
                            value: _BannerFilter.inactive,
                            label: Text('غير النشطة'),
                          ),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (selection) {
                          setState(() => _filter = selection.single);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  PrimaryScrollController.none(
                    child: _ClientBannerPreview(banners: allBanners),
                  ),
                  const SizedBox(height: 20),
                  _BannerListHeader(count: banners.length),
                  const SizedBox(height: 10),
                  if (banners.isEmpty)
                    const _EmptyBanners()
                  else
                    for (var index = 0; index < banners.length; index++) ...[
                      if (index > 0) const SizedBox(height: 8),
                      _BannerCard(
                        banner: banners[index],
                        busy: _busyBannerIds.contains(banners[index].id),
                        canMoveUp: index > 0,
                        canMoveDown: index < banners.length - 1,
                        onEdit: () => _showBannerForm(banners[index]),
                        onToggleActive: () => _confirmToggle(banners[index]),
                        onMoveUp: () =>
                            unawaited(_moveBanner(banners[index], -1)),
                        onMoveDown: () =>
                            unawaited(_moveBanner(banners[index], 1)),
                        onSortOrderChanged: (sortOrder) => unawaited(
                          _setBannerSortOrder(banners[index], sortOrder),
                        ),
                      ),
                    ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showBannerForm([AppBanner? banner]) async {
    final existing = await _loadBanners();
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
    await reloadAfterMutation(this, _reload);
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

  Future<void> _confirmToggle(AppBanner banner) async {
    final activate = !banner.active;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(activate ? 'تفعيل البانر؟' : 'إيقاف البانر؟'),
        content: Text(
          activate
              ? 'سيظهر «${banner.title}» للعملاء حسب ترتيب ظهوره.'
              : 'سيتوقف «${banner.title}» عن الظهور للعملاء من دون حذف بياناته.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(activate ? 'تفعيل' : 'إيقاف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_busyBannerIds.contains(banner.id)) return;

    setState(() => _busyBannerIds.add(banner.id));
    try {
      await ref
          .read(adminRepositoryProvider)
          .setBannerActive(banner, active: activate);
      if (!mounted) return;
      await reloadAfterMutation(this, _reload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppConfig.isDemoMode
                ? 'تم التعديل تجريبياً لهذه الجلسة فقط.'
                : activate
                    ? 'تم تفعيل البانر.'
                    : 'تم إيقاف البانر.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mutationFailureMessageAr(
              error,
              fallback:
                  'تعذر تغيير حالة البانر. تحقق من الصلاحيات والاتصال ثم أعد المحاولة.',
            ),
          ),
        ),
      );
      if (error is StaleWriteException) {
        await reloadAfterMutation(this, _reload);
      }
    } finally {
      if (mounted) {
        setState(() => _busyBannerIds.remove(banner.id));
      }
    }
  }

  Future<void> _setBannerSortOrder(AppBanner banner, int sortOrder) async {
    if (banner.sortOrder == sortOrder || _busyBannerIds.contains(banner.id)) {
      return;
    }
    setState(() => _busyBannerIds.add(banner.id));
    try {
      await ref.read(adminRepositoryProvider).saveBanner(
            banner.copyWith(sortOrder: sortOrder),
          );
      if (!mounted) return;
      await reloadAfterMutation(this, _reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mutationFailureMessageAr(
              error,
              fallback: 'تعذر حفظ رقم الترتيب. تحقق من الاتصال ثم أعد المحاولة.',
            ),
          ),
        ),
      );
      if (error is StaleWriteException) {
        await reloadAfterMutation(this, _reload);
      }
    } finally {
      if (mounted) {
        setState(() => _busyBannerIds.remove(banner.id));
      }
    }
  }

  Future<void> _moveBanner(AppBanner banner, int direction) async {
    if (_busyBannerIds.contains(banner.id)) return;
    setState(() => _busyBannerIds.add(banner.id));
    try {
      final current = await _loadBanners();
      final reordered = moveBannerInShowingOrder(
        current,
        bannerId: banner.id,
        direction: direction,
      );
      final repo = ref.read(adminRepositoryProvider);
      for (final next in reordered) {
        final previous = current.firstWhere((item) => item.id == next.id);
        if (previous.sortOrder != next.sortOrder) {
          await repo.saveBanner(next);
        }
      }
      if (!mounted) return;
      await reloadAfterMutation(this, _reload);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر تغيير ترتيب الظهور. تحقق من الاتصال ثم أعد المحاولة.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyBannerIds.remove(banner.id));
      }
    }
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
  bool saving = false;
  bool uploading = false;
  bool loadingLookups = true;
  List<String> categories = const [];
  List<Product> productResults = const [];
  Timer? productSearchDebounce;

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
    title.dispose();
    body.dispose();
    cta.dispose();
    imageUrl.dispose();
    productSearch.dispose();
    super.dispose();
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
      uploading = true;
      uploadError = null;
      saveError = null;
    });
    try {
      final images = ref.read(productImagesRepositoryProvider);
      final picked = await images.pick();
      if (!mounted) return;
      if (picked == null) {
        setState(() => uploading = false);
        return;
      }
      setState(() => imagePreviewBytes = picked.bytes);
      final result = await images.uploadPicked(
        picked,
        folder: ProductImagesRepository.bannersFolder,
      );
      if (!mounted) return;
      setState(() {
        imageUrl.text = result.publicUrl;
        uploading = false;
      });
      formKey.currentState?.validate();
    } on ProductImageUploadException catch (error) {
      if (!mounted) return;
      setState(() {
        uploading = false;
        uploadError = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        uploading = false;
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
    final targetHelp = switch (targetType) {
      'category' => 'اختر فئة من الكتالوج الحالي',
      'product' => 'ابحث عن منتج ثم اختره من القائمة',
      _ => 'يفتح الكتالوج العام ولا يحتاج قيمة إضافية.',
    };

    return AlertDialog(
      title: Text(editing ? 'تعديل البانر' : 'بانر جديد'),
      content: SizedBox(
        width: 720,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
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
                  decoration: const InputDecoration(labelText: 'الوصف المختصر'),
                ),
                TextFormField(
                  key: const ValueKey('banner-image-url-field'),
                  controller: imageUrl,
                  enabled: !saving && !uploading,
                  maxLength: 2000,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'رابط الصورة HTTPS',
                    hintText: 'https://cdn.example.com/banner.webp',
                    helperText: 'أدخل رابطاً آمناً أو ارفع صورة',
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'أضف رابط صورة أو ارفع صورة';
                    }
                    return _isSafeHttpsUrl(trimmed)
                        ? null
                        : 'استخدم رابط صورة HTTPS صالحاً ومن دون بيانات دخول';
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imagePreviewBytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          imagePreviewBytes!,
                          key: const ValueKey('banner-image-preview'),
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox(
                            width: 72,
                            height: 72,
                            child: Icon(Icons.image_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          key: const ValueKey('banner-image-upload-button'),
                          onPressed: saving ||
                                  uploading ||
                                  !ref
                                      .read(productImagesRepositoryProvider)
                                      .canUpload
                              ? null
                              : _uploadImage,
                          icon: uploading
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_file_outlined),
                          label: Text(
                            uploading ? 'جارٍ الرفع...' : 'اختيار ورفع صورة',
                          ),
                        ),
                      ),
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
                const SizedBox(height: 12),
                Text(
                  'نص زر الإجراء *',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
                                  saveError = null;
                                });
                              },
                      ),
                    ChoiceChip(
                      key: const ValueKey('banner-cta-custom-chip'),
                      label: const Text('مخصص'),
                      selected: customCta,
                      onSelected: saving
                          ? null
                          : (_) {
                              setState(() {
                                customCta = true;
                                saveError = null;
                              });
                            },
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
                    decoration: const InputDecoration(
                      labelText: 'نص الزر المخصص *',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'اكتب نص زر الإجراء'
                        : null,
                  ),
                ] else
                  FormField<String>(
                    initialValue: cta.text,
                    validator: (_) =>
                        cta.text.trim().isEmpty ? 'اكتب نص زر الإجراء' : null,
                    builder: (state) => state.hasError
                        ? Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              state.errorText!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('banner-target-type-field'),
                  initialValue: targetType,
                  decoration: const InputDecoration(labelText: 'وجهة البانر'),
                  items: const [
                    DropdownMenuItem(
                      value: 'catalog',
                      child: Text('الكتالوج العام'),
                    ),
                    DropdownMenuItem(
                      value: 'category',
                      child: Text('فئة محددة'),
                    ),
                    DropdownMenuItem(
                      value: 'product',
                      child: Text('منتج محدد'),
                    ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          setState(() {
                            targetType = value ?? 'catalog';
                            saveError = null;
                            if (targetType == 'catalog') {
                              selectedCategory = null;
                              selectedProductId = null;
                              selectedProductLabel = null;
                              productSearch.clear();
                              productResults = const [];
                            }
                            if (targetType == 'category') {
                              selectedProductId = null;
                              selectedProductLabel = null;
                              productSearch.clear();
                              productResults = const [];
                            }
                            if (targetType == 'product') {
                              selectedCategory = null;
                            }
                          });
                        },
                ),
                const SizedBox(height: 6),
                Text(
                  targetHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (targetType == 'category') ...[
                  const SizedBox(height: 8),
                  if (loadingLookups)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: ShopLoading.section(
                        message: 'جارٍ تحميل الفئات...',
                        height: 72,
                      ),
                    )
                  else if (categories.isEmpty)
                    FormField<String>(
                      validator: (_) => 'لا توجد فئات متاحة حالياً',
                      builder: (state) => Text(
                        state.errorText ?? 'لا توجد فئات متاحة حالياً',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'banner-category-field-${categories.join('|')}-$selectedCategory',
                      ),
                      initialValue: selectedCategory != null &&
                              categories.contains(selectedCategory)
                          ? selectedCategory
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'اسم الفئة *',
                        helperText: 'اختر فئة من الكتالوج الحالي',
                      ),
                      items: [
                        for (final category in categories)
                          DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setState(() => selectedCategory = value),
                      validator: (value) {
                        final resolved = value ?? selectedCategory;
                        return resolved == null || resolved.trim().isEmpty
                            ? 'اختر فئة من القائمة'
                            : null;
                      },
                    ),
                ],
                if (targetType == 'product') ...[
                  const SizedBox(height: 8),
                  if (selectedProductId != null &&
                      selectedProductId!.isNotEmpty)
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'المنتج المختار *',
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'تم اختيار: ${selectedProductLabel ?? selectedProductId}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: 'تغيير المنتج',
                            onPressed: saving
                                ? null
                                : () {
                                    setState(() {
                                      selectedProductId = null;
                                      selectedProductLabel = null;
                                      productSearch.clear();
                                      productResults = const [];
                                    });
                                  },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    TextFormField(
                      key: const ValueKey('banner-product-search-field'),
                      controller: productSearch,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'ابحث عن منتج',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: _scheduleProductSearch,
                      validator: (_) => selectedProductId == null ||
                              selectedProductId!.trim().isEmpty
                          ? 'اختر منتجاً من القائمة'
                          : null,
                    ),
                    if (productResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: productResults.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final product = productResults[index];
                              return ListTile(
                                dense: true,
                                title: Text(product.nameAr),
                                subtitle: Text(
                                  '${product.brand} · ${product.id}',
                                  textDirection: TextDirection.ltr,
                                ),
                                onTap: saving
                                    ? null
                                    : () {
                                        setState(() {
                                          selectedProductId = product.id;
                                          selectedProductLabel = product.nameAr;
                                          productSearch.clear();
                                          productResults = const [];
                                        });
                                      },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged:
                      saving ? null : (value) => setState(() => active = value),
                  title: const Text('نشط ويظهر للعملاء'),
                  subtitle: const Text(
                    'يمكن إيقافه لاحقاً من القائمة من دون حذف البيانات.',
                  ),
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
}

enum _BannerFilter { all, active, inactive }

class _BannerListHeader extends StatelessWidget {
  const _BannerListHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'قائمة البانرات',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        Text(
          '$count',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.darkGreen.withValues(alpha: .72),
              ),
        ),
      ],
    );
  }
}

class _ClientBannerPreview extends ConsumerWidget {
  const _ClientBannerPreview({required this.banners});

  final List<AppBanner> banners;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = activeBannersInShowingOrder(banners);
    final slides = HomeBannerSlide.fromAdminBanners(active);
    return DecoratedBox(
      key: const Key('admin-banner-client-preview'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.green.withValues(alpha: .14)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.darkGreen.withValues(alpha: .06),
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
            Text(
              'معاينة عرض العملاء',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              slides.isEmpty
                  ? 'لا توجد بانرات نشطة في ${ref.watch(shopBrandingProvider).shopName}.'
                  : 'شريط العروض كما يظهر للعملاء على الجوال.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkGreen.withValues(alpha: .78),
                  ),
            ),
            if (slides.isNotEmpty) ...[
              const SizedBox(height: 10),
              _CustomerBannerPreviewStage(
                child: OfferBannerCarousel(
                  key: const Key('admin-banner-client-carousel'),
                  banners: slides,
                  preview: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Phone-width card so the shared [OfferBannerCarousel] stays mobile-sized
/// without a fake device bezel, thick black border, or home-indicator pill.
class _CustomerBannerPreviewStage extends StatelessWidget {
  const _CustomerBannerPreviewStage({required this.child});

  final Widget child;

  static const double _previewWidth = 390;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _previewWidth),
        child: DecoratedBox(
          key: const Key('admin-banner-client-preview-stage'),
          decoration: BoxDecoration(
            color: AppTheme.sand,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.green.withValues(alpha: .16)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.darkGreen.withValues(alpha: .06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.banner,
    required this.busy,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onToggleActive,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onSortOrderChanged,
  });

  final AppBanner banner;
  final bool busy;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<int> onSortOrderChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('banner-card-${banner.id}'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 108,
            child: Image.network(
              banner.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: Color(0xFFE8F1EC),
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 48,
                    color: AppTheme.green,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  banner.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (banner.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    banner.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${_targetLabel(banner.targetType)}'
                  '${banner.targetValue.isEmpty ? '' : ': ${banner.targetValue}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                  textDirection: banner.targetType == 'url'
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                ),
                const SizedBox(height: 4),
                Text(
                  'زر الإجراء: ${banner.ctaText}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  key: ValueKey('banner-actions-${banner.id}'),
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusChip(active: banner.active),
                    _BannerSortOrderField(
                      bannerId: banner.id,
                      sortOrder: banner.sortOrder,
                      enabled: !busy,
                      onSubmit: onSortOrderChanged,
                    ),
                    IconButton(
                      key: ValueKey('banner-move-up-${banner.id}'),
                      tooltip: 'تقديم في العرض',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      onPressed: busy || !canMoveUp ? null : onMoveUp,
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      key: ValueKey('banner-move-down-${banner.id}'),
                      tooltip: 'تأخير في العرض',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      onPressed: busy || !canMoveDown ? null : onMoveDown,
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onEdit,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('تعديل'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onToggleActive,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              banner.active
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 18,
                            ),
                      label: Text(banner.active ? 'إيقاف' : 'تفعيل'),
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
  const _StatusChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        active ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 16,
        color: active ? AppTheme.green : Colors.grey.shade700,
      ),
      label: Text(active ? 'نشط' : 'غير نشط'),
      backgroundColor: active
          ? AppTheme.green.withValues(alpha: .10)
          : Colors.grey.withValues(alpha: .12),
      visualDensity: VisualDensity.compact,
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

String _targetLabel(String targetType) => switch (targetType) {
      'category' => 'فئة',
      'product' => 'منتج',
      'url' => 'رابط خارجي',
      _ => 'الكتالوج العام',
    };

bool _isSafeHttpsUrl(String? raw) {
  final uri = Uri.tryParse(raw?.trim() ?? '');
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}
