import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/product_images_repository.dart';
import '../admin_dashboard/admin_shell.dart';

int nextBannerSortOrder(Iterable<AppBanner> banners) {
  var maxOrder = -1;
  for (final banner in banners) {
    if (banner.sortOrder > maxOrder) {
      maxOrder = banner.sortOrder;
    }
  }
  return maxOrder < 0 ? 0 : maxOrder + 1;
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

  void _reload() {
    setState(() => _bannersFuture = _loadBanners());
  }

  @override
  Widget build(BuildContext context) {
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
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _BannerLoadError(onRetry: _reload);
          }

          final banners = (snapshot.data ?? const <AppBanner>[])
              .where(
                (banner) => switch (_filter) {
                  _BannerFilter.all => true,
                  _BannerFilter.active => banner.active,
                  _BannerFilter.inactive => !banner.active,
                },
              )
              .toList(growable: false);

          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1200
                  ? 3
                  : constraints.maxWidth >= 720
                      ? 2
                      : 1;
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (AppConfig.isDemoMode) ...[
                            const _DemoBannerNotice(),
                            const SizedBox(height: 12),
                          ],
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
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
                              FilledButton.icon(
                                onPressed: () => _showBannerForm(),
                                icon: const Icon(Icons.add),
                                label: const Text('بانر جديد'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'أضف بانرات بصور آمنة ووجّه العميل إلى الكتالوج أو فئة أو منتج.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (banners.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyBanners(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 420,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final banner = banners[index];
                            return _BannerCard(
                              banner: banner,
                              busy: _busyBannerIds.contains(banner.id),
                              onEdit: () => _showBannerForm(banner),
                              onToggleActive: () => _confirmToggle(banner),
                            );
                          },
                          childCount: banners.length,
                        ),
                      ),
                    ),
                ],
              );
            },
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
    _reload();
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

    setState(() => _busyBannerIds.add(banner.id));
    try {
      await ref
          .read(adminRepositoryProvider)
          .setBannerActive(banner, active: activate);
      if (!mounted) return;
      _reload();
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر تغيير حالة البانر. تحقق من الصلاحيات والاتصال ثم أعد المحاولة.',
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
    targetType = legacyUrl ||
            !AppBanner.supportedTargetTypes.contains(initialTarget)
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
      final result =
          await ref.read(productImagesRepositoryProvider).pickAndUploadBanner();
      if (!mounted || result == null) {
        if (mounted) setState(() => uploading = false);
        return;
      }
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        uploading = false;
        uploadError =
            'تعذر رفع الصورة. تحقق من الاتصال ثم حاول من جديد، أو استخدم رابط HTTPS.';
      });
    }
  }

  Future<void> _save() async {
    if (formKey.currentState?.validate() != true) return;
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
    );
    try {
      final result = await ref.read(adminRepositoryProvider).saveBanner(draft);
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        saveError =
            'تعذر حفظ البانر. تحقق من البيانات والصلاحيات والاتصال ثم أعد المحاولة.';
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
                  decoration:
                      const InputDecoration(labelText: 'الوصف المختصر'),
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
                Align(
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: Text(
                      uploading ? 'جارٍ الرفع...' : 'اختيار ورفع صورة',
                    ),
                  ),
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
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'اكتب نص زر الإجراء'
                            : null,
                  ),
                ] else
                  FormField<String>(
                    initialValue: cta.text,
                    validator: (_) => cta.text.trim().isEmpty
                        ? 'اكتب نص زر الإجراء'
                        : null,
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
                  decoration:
                      const InputDecoration(labelText: 'وجهة البانر'),
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
                      child: Center(child: CircularProgressIndicator()),
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
                          : (value) =>
                              setState(() => selectedCategory = value),
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
                                          selectedProductLabel =
                                              product.nameAr;
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
                  onChanged: saving
                      ? null
                      : (value) => setState(() => active = value),
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
                        color:
                            Theme.of(context).colorScheme.onErrorContainer,
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

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.banner,
    required this.busy,
    required this.onEdit,
    required this.onToggleActive,
  });

  final AppBanner banner;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 142,
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatusChip(active: banner.active),
                      Chip(
                        avatar: const Icon(Icons.sort, size: 16),
                        label: Text('الترتيب ${banner.sortOrder}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    banner.title,
                    maxLines: 1,
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
                  const SizedBox(height: 8),
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
                  const Spacer(),
                  Text(
                    'زر الإجراء: ${banner.ctaText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy ? null : onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('تعديل'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : onToggleActive,
                        icon: busy
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                banner.active
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline,
                              ),
                        label: Text(banner.active ? 'إيقاف' : 'تفعيل'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

class _EmptyBanners extends StatelessWidget {
  const _EmptyBanners();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_carousel_outlined, size: 54),
            SizedBox(height: 12),
            Text(
              'لا توجد بانرات بهذا الفلتر',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text('أنشئ بانراً جديداً أو غيّر فلتر الحالة.'),
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
