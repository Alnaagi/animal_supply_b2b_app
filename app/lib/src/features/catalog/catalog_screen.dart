import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/price_text.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../cart/cart_controller.dart';
import 'catalog_filters.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({this.initialCategory, super.key});
  final String? initialCategory;

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

  @override
  void initState() {
    super.initState();
    category = widget.initialCategory;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_reloadCatalog(refreshMetadata: true));
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
        : Future<List<String>?>.value(null);
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
          categories = _filterValues(
            loadedCategories,
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

  Future<List<String>?> _loadCategoriesSafely() async {
    try {
      return await ref.read(catalogRepositoryProvider).categories();
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: FilterChip(
                    label: const Text('الكل'),
                    selected: category == null,
                    onSelected: (_) => _selectCategory(null),
                  ),
                ),
                for (final value in categories)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                      label: Text(value),
                      selected: category == value,
                      onSelected: (_) => _selectCategory(value),
                    ),
                  ),
              ],
            ),
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
            const Center(child: CircularProgressIndicator())
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
            for (final product in products) ProductListCard(product: product),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                child: FilledButton.tonalIcon(
                  key: const ValueKey('catalog-load-more'),
                  onPressed: loadingMore ? null : _loadMore,
                  icon: loadingMore
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
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

class ProductListCard extends ConsumerWidget {
  const ProductListCard({required this.product, super.key});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.push('/product/${product.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProductImagePlaceholder(
                category: product.category,
                productId: product.id,
                imageUrl: product.imageUrl,
                size: 86),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  if (product.brand.trim().isNotEmpty)
                    Text(
                      product.brand,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _MiniChip(
                      product.customerAvailabilityLabel,
                      color:
                          product.isOrderable ? AppTheme.green : AppTheme.red,
                    ),
                    _MiniChip(
                      'أقل جملة ${product.minOrderQuantity}',
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'سعر الجملة',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                            PriceText(
                              price: product.price,
                            ),
                            if (product.retailUnitPrice != null)
                              Text(
                                'بيع الوحدة المقترح: '
                                '${product.retailUnitPrice!.toStringAsFixed(2)} د.ل',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton.filled(
                          tooltip: product.isOrderable
                              ? 'إضافة ${product.name} إلى السلة'
                              : 'المنتج غير متوفر',
                          onPressed: product.isOrderable
                              ? () => ref
                                  .read(cartControllerProvider.notifier)
                                  .add(product)
                              : null,
                          icon: const Icon(Icons.add)),
                    ],
                  ),
                ])),
          ]),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label, {this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: (color ?? Colors.grey).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color ?? Colors.grey.shade700,
                fontWeight: FontWeight.w700)),
      );
}

List<Product> _deduplicateProducts(Iterable<Product> source) {
  final seen = <String>{};
  return [
    for (final product in source)
      if (seen.add(product.id)) product,
  ];
}
