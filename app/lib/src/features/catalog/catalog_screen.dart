import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/refresh/screen_reload.dart';
import '../../core/theme/app_theme.dart';
import '../../core/connectivity/connectivity_provider.dart';
import '../../core/widgets/category_icon_view.dart';
import '../../core/widgets/customer_product_summary.dart'
    show
        AddToCartPill,
        CustomerProductCardCopy,
        DiscountBadge,
        WholesalePriceBlock;

import '../../core/widgets/empty_state.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/product_info_chip.dart';
import '../../core/widgets/shop_loading.dart';
import '../../core/widgets/shop_refresh_indicator.dart';
import '../../data/local/catalog_view_mode_store.dart';
import '../../data/models/product.dart';
import '../../data/models/product_category.dart';
import '../../data/repositories/catalog_repository.dart';
import '../cart/added_to_cart_prompt.dart';
import 'catalog_filters.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({
    this.initialCategory,
    this.viewModeStore,
    super.key,
  });
  final String? initialCategory;
  final CatalogViewModeStore? viewModeStore;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  static const _searchDebounceDuration = Duration(milliseconds: 350);
  static const _pageSize = CatalogRepository.defaultPageSize;

  String query = '';
  String? category;
  CatalogFilters filters = const CatalogFilters();
  List<Product> products = const [];
  List<String> categories = const [];
  List<ProductCategory> categoryModels = const [];
  CatalogFilterOptions filterOptions = const CatalogFilterOptions();
  bool initialLoading = true;
  bool loadingMore = false;
  bool hasMore = false;
  bool categoriesLoaded = false;
  bool filterOptionsLoaded = false;
  Object? loadError;
  int nextOffset = 0;
  int loadRevision = 0;
  int offlineSnapshotCount = 0;
  DateTime? snapshotAt;
  CatalogPageSource pageSource = CatalogPageSource.demo;
  Timer? _searchDebounce;
  late final CatalogViewModeStore _viewModeStore;
  CatalogViewMode _viewMode = CatalogViewMode.comfortable;

  @override
  void initState() {
    super.initState();
    category = widget.initialCategory;
    _viewModeStore = widget.viewModeStore ?? CatalogViewModeStore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_restoreViewModePreference());
      unawaited(_reloadCatalog(refreshMetadata: true));
    });
  }

  @override
  void didUpdateWidget(covariant CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) {
      category = widget.initialCategory;
      unawaited(_reloadCatalog());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _updateQuery(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      query = value;
      unawaited(_reloadCatalog());
    });
  }

  void _selectCategory(String? value) {
    if (category == value) return;
    setState(() => category = value);
    unawaited(_reloadCatalog());
  }

  Future<CatalogPage> _loadPage({
    DateTime? pageSnapshot,
    int offset = 0,
  }) {
    return ref.read(catalogRepositoryProvider).productsPage(
          query: query,
          category: category,
          brand: filters.brand,
          animalType: filters.animalType,
          unitSize: filters.unitSize,
          minimumPrice: filters.minimumPrice,
          maximumPrice: filters.maximumPrice,
          availability: filters.availability.queryValue,
          snapshotAt: pageSnapshot,
          offset: offset,
          pageSize: _pageSize,
        );
  }

  Future<void> _reloadCatalog({bool refreshMetadata = false}) async {
    ref.read(remoteActivityProvider.notifier).begin();
    try {
      await _reloadCatalogBody(refreshMetadata: refreshMetadata);
    } finally {
      ref.read(remoteActivityProvider.notifier).end();
    }
  }

  Future<void> _reloadCatalogBody({bool refreshMetadata = false}) async {
    final revision = ++loadRevision;
    if (mounted) {
      setState(() {
        initialLoading = true;
        loadingMore = false;
        loadError = null;
        products = const [];
        hasMore = false;
        nextOffset = 0;
        snapshotAt = null;
        offlineSnapshotCount = 0;
      });
    }

    final categoriesFuture = refreshMetadata || !categoriesLoaded
        ? _loadCategoriesSafely()
        : Future<List<ProductCategory>?>.value(null);
    final optionsFuture = refreshMetadata || !filterOptionsLoaded
        ? _loadFilterOptionsSafely()
        : Future<CatalogFilterOptions?>.value(null);
    try {
      final page = await _loadPage();
      final loadedCategories = await categoriesFuture;
      final loadedOptions = await optionsFuture;
      if (!mounted || revision != loadRevision) return;
      setState(() {
        products = page.products;
        hasMore = page.hasMore;
        nextOffset = page.nextOffset;
        snapshotAt = page.snapshotAt;
        pageSource = page.source;
        offlineSnapshotCount = page.offlineSnapshotCount;
        if (loadedCategories != null) {
          categoryModels = loadedCategories;
          categories = _filterValues(
            loadedCategories.map((item) => item.name),
            selected: category,
          );
          categoriesLoaded = true;
        }
        if (loadedOptions != null) {
          filterOptions = loadedOptions;
          filterOptionsLoaded = true;
        }
        initialLoading = false;
      });
    } catch (error) {
      await categoriesFuture;
      await optionsFuture;
      if (!mounted || revision != loadRevision) return;
      setState(() {
        loadError = error;
        initialLoading = false;
      });
    }
  }

  Future<List<ProductCategory>?> _loadCategoriesSafely() async {
    try {
      return await ref.read(catalogRepositoryProvider).productCategories();
    } catch (_) {
      return null;
    }
  }

  Future<CatalogFilterOptions?> _loadFilterOptionsSafely() async {
    try {
      return await ref.read(catalogRepositoryProvider).filterOptions();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMore() async {
    final pageSnapshot = snapshotAt;
    if (loadingMore || !hasMore || pageSnapshot == null) return;
    final revision = loadRevision;
    setState(() => loadingMore = true);
    try {
      final page = await _loadPage(
        pageSnapshot: pageSnapshot,
        offset: nextOffset,
      );
      if (!mounted || revision != loadRevision) return;
      setState(() {
        products = _deduplicateProducts([...products, ...page.products]);
        hasMore = page.hasMore;
        nextOffset = page.nextOffset;
        pageSource = page.source;
        offlineSnapshotCount = page.offlineSnapshotCount;
        loadingMore = false;
      });
    } catch (_) {
      if (!mounted || revision != loadRevision) return;
      setState(() => loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('تعذر تحميل منتجات إضافية. تحقق من الاتصال وحاول مجدداً.'),
        ),
      );
    }
  }

  void _clearFilters() {
    if (filters.isEmpty) return;
    setState(() => filters = const CatalogFilters());
    unawaited(_reloadCatalog());
  }

  Future<void> _restoreViewModePreference() async {
    final fallback = CatalogViewModeStore.defaultForWidth(
      MediaQuery.sizeOf(context).width,
    );
    final restored = await _viewModeStore.load(fallbackMode: fallback);
    if (!mounted) return;
    setState(() => _viewMode = restored);
  }

  Future<void> _selectViewMode(CatalogViewMode mode) async {
    if (_viewMode == mode) return;
    setState(() => _viewMode = mode);
    await _viewModeStore.save(mode);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(networkRetryTickProvider, (previous, next) {
      if (previous != next) {
        unawaited(_reloadCatalog(refreshMetadata: true));
      }
    });
    listenForScreenReload(
      ref,
      () => _reloadCatalog(refreshMetadata: true),
    );
    return ShopRefreshIndicator(
      onRefresh: () => _reloadCatalog(refreshMetadata: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'المنتجات',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth >= 620
                      ? constraints.maxWidth - 174
                      : constraints.maxWidth,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'ابحث باسم المنتج أو الشركة',
                    ),
                    onChanged: _updateQuery,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: initialLoading ? null : _showFilters,
                  icon: Badge(
                    isLabelVisible: !filters.isEmpty,
                    label: Text('${filters.activeCount}'),
                    child: const Icon(Icons.tune),
                  ),
                  label: const Text('فلترة متقدمة'),
                ),
                _CatalogViewModeToggle(
                  mode: _viewMode,
                  onChanged: _selectViewMode,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ProductChipWrap(
            key: const ValueKey('catalog-category-chips'),
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('الكل'),
                selected: category == null,
                onSelected: (_) => _selectCategory(null),
              ),
              for (final value in categories)
                FilterChip(
                  avatar: CategoryIconView.fromCategory(
                    _categoryModelByName(value),
                    size: 18,
                  ),
                  label: Text(value),
                  selected: category == value,
                  onSelected: (_) => _selectCategory(value),
                ),
            ],
          ),
          if (!filters.isEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.green.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_alt_outlined,
                    color: AppTheme.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _filtersSummary(filters),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('مسح'),
                  ),
                ],
              ),
            ),
          ],
          if (pageSource == CatalogPageSource.offlineSnapshot) ...[
            const SizedBox(height: 10),
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.offline_bolt_outlined),
                title: const Text('عرض نسخة محفوظة محدودة'),
                subtitle: Text(
                  'تعذر الوصول للخادم. البحث والفلترة يعملان داخل آخر '
                  '$offlineSnapshotCount منتج محفوظ على هذا الجهاز '
                  '(الحد الأقصى ${CatalogRepository.offlineSnapshotLimit}).',
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (initialLoading)
            const ShopLoading.section(
              message: 'جارٍ تحميل المنتجات...',
            )
          else if (loadError != null)
            EmptyState(
              key: const Key('catalog-load-error'),
              title: 'تعذر تحميل المنتجات',
              message:
                  'تعذر الوصول إلى بيانات المنتجات ولا توجد نسخة محفوظة لهذا الحساب.',
              icon: Icons.cloud_off_outlined,
              action: FilledButton.icon(
                key: const Key('catalog-retry-button'),
                onPressed: () => _reloadCatalog(refreshMetadata: true),
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            )
          else if (products.isEmpty)
            const EmptyState(
              title: 'لا توجد منتجات',
              message: 'جرّب بحثاً آخر أو اختر تصنيفاً مختلفاً.',
              icon: Icons.search_off,
            )
          else ...[
            _CatalogProductsLayout(
              products: products,
              mode: _viewMode,
            ),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                child: FilledButton.tonalIcon(
                  key: const ValueKey('catalog-load-more'),
                  onPressed: loadingMore ? null : _loadMore,
                  icon: loadingMore
                      ? const ShopLoading.compact()
                      : const Icon(Icons.expand_more),
                  label: Text(
                    loadingMore
                        ? 'جارٍ تحميل منتجات إضافية...'
                        : 'تحميل المزيد',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _showFilters() async {
    final brands = _filterValues(
      filterOptions.brands,
      selected: filters.brand,
    );
    final animalTypes = _filterValues(
      filterOptions.animalTypes,
      selected: filters.animalType,
    );
    final unitSizes = _filterValues(
      filterOptions.unitSizes,
      selected: filters.unitSize,
    );
    var brand = filters.brand;
    var animalType = filters.animalType;
    var unitSize = filters.unitSize;
    var availability = filters.availability;
    final minimumPrice = TextEditingController(
      text: filters.minimumPrice?.toStringAsFixed(2) ?? '',
    );
    final maximumPrice = TextEditingController(
      text: filters.maximumPrice?.toStringAsFixed(2) ?? '',
    );
    String? validationMessage;

    final selected = await showDialog<CatalogFilters>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('فلترة المنتجات'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: brand,
                    decoration:
                        const InputDecoration(labelText: 'العلامة / المورّد'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('كل العلامات'),
                      ),
                      for (final value in brands)
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) => setDialogState(() => brand = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: animalType,
                    decoration: const InputDecoration(labelText: 'نوع الحيوان'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('كل أنواع الحيوانات'),
                      ),
                      for (final value in animalTypes)
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => animalType = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: unitSize,
                    decoration:
                        const InputDecoration(labelText: 'الحجم / العبوة'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('كل الأحجام'),
                      ),
                      for (final value in unitSizes)
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => unitSize = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<CatalogAvailability>(
                    initialValue: availability,
                    decoration:
                        const InputDecoration(labelText: 'حالة المخزون'),
                    items: const [
                      DropdownMenuItem(
                        value: CatalogAvailability.all,
                        child: Text('الكل'),
                      ),
                      DropdownMenuItem(
                        value: CatalogAvailability.inStock,
                        child: Text('متوفر للطلب'),
                      ),
                      DropdownMenuItem(
                        value: CatalogAvailability.lowStock,
                        child: Text('مخزون منخفض'),
                      ),
                      DropdownMenuItem(
                        value: CatalogAvailability.outOfStock,
                        child: Text('غير متوفر'),
                      ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => availability = value ?? CatalogAvailability.all,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minimumPrice,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration:
                              const InputDecoration(labelText: 'أقل سعر'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: maximumPrice,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration:
                              const InputDecoration(labelText: 'أعلى سعر'),
                        ),
                      ),
                    ],
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  brand = null;
                  animalType = null;
                  unitSize = null;
                  availability = CatalogAvailability.all;
                  validationMessage = null;
                  minimumPrice.clear();
                  maximumPrice.clear();
                });
              },
              child: const Text('إعادة ضبط'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final minimum = _optionalMoney(minimumPrice.text);
                final maximum = _optionalMoney(maximumPrice.text);
                if (minimum == double.negativeInfinity ||
                    maximum == double.negativeInfinity ||
                    (minimum != null && maximum != null && minimum > maximum)) {
                  setDialogState(() {
                    validationMessage =
                        'أدخل أسعاراً غير سالبة، واجعل أعلى سعر أكبر من أو يساوي أقل سعر.';
                  });
                  return;
                }
                Navigator.pop(
                  context,
                  CatalogFilters(
                    brand: brand,
                    animalType: animalType,
                    unitSize: unitSize,
                    minimumPrice: minimum,
                    maximumPrice: maximum,
                    availability: availability,
                  ),
                );
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
    minimumPrice.dispose();
    maximumPrice.dispose();
    if (selected != null && mounted) {
      setState(() => filters = selected);
      unawaited(_reloadCatalog());
    }
  }

  ProductCategory _categoryModelByName(String name) {
    for (final item in categoryModels) {
      if (item.name == name) return item;
    }
    return ProductCategory(id: name, name: name);
  }

  static List<String> _filterValues(
    Iterable<String> values, {
    String? selected,
  }) {
    final result = <String>{
      if (selected?.trim().isNotEmpty == true) selected!.trim(),
      for (final value in values)
        if (value.trim().isNotEmpty) value.trim(),
    }.toList()
      ..sort();
    return result;
  }

  static double? _optionalMoney(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      return double.negativeInfinity;
    }
    return parsed;
  }

  static String _filtersSummary(CatalogFilters filters) {
    final labels = <String>[
      if (filters.brand != null) 'العلامة: ${filters.brand}',
      if (filters.animalType != null) 'الحيوان: ${filters.animalType}',
      if (filters.unitSize != null) 'العبوة: ${filters.unitSize}',
      if (filters.minimumPrice != null)
        'السعر من ${filters.minimumPrice!.toStringAsFixed(2)} د.ل',
      if (filters.maximumPrice != null)
        'السعر إلى ${filters.maximumPrice!.toStringAsFixed(2)} د.ل',
      if (filters.availability != CatalogAvailability.all)
        switch (filters.availability) {
          CatalogAvailability.inStock => 'متوفر للطلب',
          CatalogAvailability.lowStock => 'مخزون منخفض',
          CatalogAvailability.outOfStock => 'غير متوفر',
          CatalogAvailability.all => '',
        },
    ];
    return labels.join(' • ');
  }
}

class _CatalogViewModeToggle extends StatelessWidget {
  const _CatalogViewModeToggle({
    required this.mode,
    required this.onChanged,
  });

  final CatalogViewMode mode;
  final ValueChanged<CatalogViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CatalogViewModeButton(
            key: const ValueKey('catalog-view-mode-comfortable'),
            tooltip: 'عرض مريح',
            icon: Icons.view_agenda_outlined,
            selected: mode == CatalogViewMode.comfortable,
            onPressed: () => onChanged(CatalogViewMode.comfortable),
          ),
          _CatalogViewModeButton(
            key: const ValueKey('catalog-view-mode-compact'),
            tooltip: 'عرض مختصر',
            icon: Icons.view_headline_outlined,
            selected: mode == CatalogViewMode.compact,
            onPressed: () => onChanged(CatalogViewMode.compact),
          ),
          _CatalogViewModeButton(
            key: const ValueKey('catalog-view-mode-grid'),
            tooltip: 'عرض شبكي',
            icon: Icons.grid_view_rounded,
            selected: mode == CatalogViewMode.grid,
            onPressed: () => onChanged(CatalogViewMode.grid),
          ),
        ],
      ),
    );
  }
}

class _CatalogViewModeButton extends StatelessWidget {
  const _CatalogViewModeButton({
    required super.key,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        selected: selected,
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor:
                selected ? colorScheme.primaryContainer : Colors.transparent,
            foregroundColor: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _CatalogProductsLayout extends StatelessWidget {
  const _CatalogProductsLayout({
    required this.products,
    required this.mode,
  });

  final List<Product> products;
  final CatalogViewMode mode;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case CatalogViewMode.comfortable:
        return Column(
          key: const ValueKey('catalog-comfortable-view'),
          children: [
            for (final product in products) ProductListCard(product: product),
          ],
        );
      case CatalogViewMode.compact:
        return Column(
          key: const ValueKey('catalog-compact-view'),
          children: [
            for (final product in products)
              ProductCompactCard(product: product),
          ],
        );
      case CatalogViewMode.grid:
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = switch (width) {
              >= 1400 => 4,
              >= 1000 => 3,
              _ => 2,
            };
            return GridView.builder(
              key: const ValueKey('catalog-grid-view'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: .66,
              ),
              itemCount: products.length,
              itemBuilder: (context, index) => ProductGridCard(
                product: products[index],
              ),
            );
          },
        );
    }
  }
}

class ProductListCard extends ConsumerWidget {
  const ProductListCard({required this.product, super.key});
  final Product product;

  static const _imagePanelWidth = 112.0;
  static const _radius = 16.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = CustomerProductCardCopy.packSize(product);
    return Card(
      key: Key('catalog-product-card-${product.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: .16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: InkWell(
        onTap: () => context.push('/product/${product.id}'),
        child: Stack(
          children: [
            Positioned.directional(
              textDirection: Directionality.of(context),
              start: 0,
              top: 0,
              bottom: 0,
              width: _imagePanelWidth,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImagePlaceholder(
                    key: Key('catalog-product-image-${product.id}'),
                    category: product.category,
                    productId: product.id,
                    imageUrl: product.imageUrl,
                    semanticLabel: 'صورة ${product.name}',
                    expand: true,
                    borderRadius: BorderRadius.zero,
                  ),
                  if (product.hasProductDiscount)
                    PositionedDirectional(
                      top: 6,
                      start: 6,
                      child: DiscountBadge(
                        discountPercent: product.discountPercent!,
                        compact: true,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                _imagePanelWidth + 12,
                12,
                12,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  if (CustomerProductCardCopy.brand(product).isNotEmpty)
                    Text(
                      CustomerProductCardCopy.brand(product),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.darkGreen.withValues(alpha: .62),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 6),
                  ProductChipWrap(children: [
                    Tooltip(
                      message: product.isOrderable
                          ? AddedToCartPromptCopy.orderActionTooltip
                          : product.customerAvailabilityLabel,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: product.isOrderable
                            ? () => addProductToCartThenPrompt(
                                  context: context,
                                  ref: ref,
                                  product: product,
                                )
                            : null,
                        child: ProductInfoChip(
                          product.customerAvailabilityLabel,
                          color: product.isOrderable
                              ? AppTheme.green
                              : AppTheme.red,
                        ),
                      ),
                    ),
                    if (pack.isNotEmpty)
                      ProductInfoChip(
                        pack,
                        color: AppTheme.green,
                      ),
                    ProductInfoChip(
                      'أقل جملة ${product.minOrderQuantity}',
                    ),
                    if (product.unitsPerBoxLabel != null)
                      ProductInfoChip(product.unitsPerBoxLabel!),
                  ]),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: WholesalePriceBlock(
                          product: product,
                          showWholesaleLabel: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AddToCartPill(
                        enabled: product.isOrderable,
                        tooltip: product.isOrderable
                            ? 'إضافة ${product.name} إلى السلة'
                            : 'المنتج غير متوفر',
                        onPressed: product.isOrderable
                            ? () => addProductToCartThenPrompt(
                                  context: context,
                                  ref: ref,
                                  product: product,
                                )
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductCompactCard extends ConsumerWidget {
  const ProductCompactCard({required this.product, super.key});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = CustomerProductCardCopy.packSize(product);
    return Card(
      key: Key('catalog-compact-card-${product.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push('/product/${product.id}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 70,
                  height: 70,
                  child: ProductImagePlaceholder(
                    category: product.category,
                    productId: product.id,
                    imageUrl: product.imageUrl,
                    semanticLabel: 'صورة ${product.name}',
                    expand: true,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    if (CustomerProductCardCopy.brand(product).isNotEmpty)
                      Text(
                        CustomerProductCardCopy.brand(product),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.darkGreen.withValues(alpha: .62),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ProductInfoChip(
                          product.customerAvailabilityLabel,
                          color: product.isOrderable
                              ? AppTheme.green
                              : AppTheme.red,
                        ),
                        if (pack.isNotEmpty)
                          ProductInfoChip(
                            pack,
                            color: AppTheme.green,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    WholesalePriceBlock(
                      product: product,
                      showWholesaleLabel: false,
                    ),
                    const SizedBox(height: 6),
                    AddToCartPill(
                      enabled: product.isOrderable,
                      tooltip: product.isOrderable
                          ? 'إضافة ${product.name} إلى السلة'
                          : 'المنتج غير متوفر',
                      onPressed: product.isOrderable
                          ? () => addProductToCartThenPrompt(
                                context: context,
                                ref: ref,
                                product: product,
                              )
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductGridCard extends ConsumerWidget {
  const ProductGridCard({required this.product, super.key});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = CustomerProductCardCopy.packSize(product);
    return Card(
      key: Key('catalog-grid-card-${product.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () => context.push('/product/${product.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImagePlaceholder(
                    category: product.category,
                    productId: product.id,
                    imageUrl: product.imageUrl,
                    semanticLabel: 'صورة ${product.name}',
                    expand: true,
                    borderRadius: BorderRadius.zero,
                  ),
                  if (product.hasProductDiscount)
                    PositionedDirectional(
                      top: 6,
                      start: 6,
                      child: DiscountBadge(
                        discountPercent: product.discountPercent!,
                        compact: true,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  if (pack.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ProductInfoChip(
                      pack,
                      color: AppTheme.green,
                    ),
                  ],
                  const SizedBox(height: 6),
                  ProductInfoChip(
                    product.customerAvailabilityLabel,
                    color: product.isOrderable ? AppTheme.green : AppTheme.red,
                  ),
                  const SizedBox(height: 8),
                  WholesalePriceBlock(
                    product: product,
                    showWholesaleLabel: false,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: AddToCartPill(
                      enabled: product.isOrderable,
                      tooltip: product.isOrderable
                          ? 'إضافة ${product.name} إلى السلة'
                          : 'المنتج غير متوفر',
                      onPressed: product.isOrderable
                          ? () => addProductToCartThenPrompt(
                                context: context,
                                ref: ref,
                                product: product,
                              )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Product> _deduplicateProducts(Iterable<Product> source) {
  final seen = <String>{};
  return [
    for (final product in source)
      if (seen.add(product.id)) product,
  ];
}
