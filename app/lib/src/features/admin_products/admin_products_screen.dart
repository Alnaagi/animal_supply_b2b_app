import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/responsive_field_group.dart';
import '../../data/models/product.dart';
import '../../data/models/product_category.dart';
import '../../data/repositories/catalog_repository.dart';
import '../admin_dashboard/admin_shell.dart';

class AdminProductsScreen extends ConsumerStatefulWidget {
  const AdminProductsScreen({
    super.key,
    this.openCreateForm = false,
  });

  final bool openCreateForm;

  @override
  ConsumerState<AdminProductsScreen> createState() =>
      _AdminProductsScreenState();
}

class _AdminProductsScreenState extends ConsumerState<AdminProductsScreen> {
  static const _pageSize = CatalogRepository.defaultPageSize;

  final search = TextEditingController();
  String? category;
  String? brand;
  String? animalType;
  String? unitSize;
  double? minimumPrice;
  double? maximumPrice;
  String availability = 'all';
  List<Product> products = const [];
  List<String> categories = const [];
  List<String> brands = const [];
  List<String> animalTypes = const [];
  List<String> unitSizes = const [];
  _AdminProductViewMode viewMode = _AdminProductViewMode.detailed;
  _AdminProductSort sort = _AdminProductSort.newest;
  bool initialLoading = true;
  bool loadingMore = false;
  bool hasMore = false;
  bool metadataLoaded = false;
  Object? loadError;
  int nextOffset = 0;
  int loadRevision = 0;
  int offlineSnapshotCount = 0;
  DateTime? snapshotAt;
  CatalogPageSource pageSource = CatalogPageSource.demo;
  bool _openedCreateForm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_reloadProducts(refreshMetadata: true));
      _maybeOpenCreateForm();
    });
  }

  @override
  void didUpdateWidget(covariant AdminProductsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openCreateForm && !oldWidget.openCreateForm) {
      _openedCreateForm = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeOpenCreateForm();
      });
    }
  }

  void _maybeOpenCreateForm() {
    if (!widget.openCreateForm || _openedCreateForm || !mounted) return;
    _openedCreateForm = true;
    context.replace('/admin/products');
    unawaited(_showProductForm());
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'إدارة المنتجات',
      actions: [
        IconButton(
          key: const ValueKey('refresh-admin-products-button'),
          onPressed: initialLoading
              ? null
              : () => unawaited(
                    _reloadProducts(refreshMetadata: true),
                  ),
          icon: initialLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: 'تحديث المنتجات والتصنيفات',
        ),
        IconButton(
            onPressed: () => _showProductForm(),
            icon: const Icon(Icons.add_box),
            tooltip: 'منتج جديد')
      ],
      child: RefreshIndicator(
        onRefresh: () => _reloadProducts(refreshMetadata: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            TextField(
              key: const ValueKey('admin-products-search'),
              controller: search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'بحث باسم المنتج أو الشركة',
              ),
              onSubmitted: (_) => unawaited(_reloadProducts()),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    key: const ValueKey('admin-products-category-all'),
                    label: const Text('الكل'),
                    selected: category == null,
                    onSelected: (_) => _selectCategory(null),
                  ),
                  for (final value in categories) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      key: ValueKey('admin-products-category-$value'),
                      label: Text(value),
                      selected: category == value,
                      onSelected: (_) => _selectCategory(value),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('create-category-button'),
                  onPressed: _createCategory,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('تصنيف جديد'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('manage-categories-button'),
                  onPressed: _showCategoryManager,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('إدارة التصنيفات'),
                ),
                FilledButton.icon(
                  onPressed: () => _showProductForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('منتج جديد'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _AdminProductsBrowseToolbar(
              viewMode: viewMode,
              sort: sort,
              activeFilterCount: _activeFilterCount,
              resultCount: products.length,
              hasMore: hasMore,
              onViewModeChanged: (value) {
                if (value == viewMode) return;
                setState(() => viewMode = value);
              },
              onSortChanged: _selectSort,
              onOpenFilters: _showProductFilters,
              onClearFilters:
                  _activeFilterCount == 0 ? null : _clearProductFilters,
            ),
            if (_activeFilterCount > 0) ...[
              const SizedBox(height: 8),
              _AdminProductActiveFilters(
                chips: _activeFilterChips(),
                onClearAll: _clearProductFilters,
              ),
            ],
            if (pageSource == CatalogPageSource.offlineSnapshot) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.offline_bolt_outlined),
                  title: const Text('عرض نسخة إدارية محفوظة ومحدودة'),
                  subtitle: Text(
                    'تعذر الوصول للخادم. النتائج الحالية من آخر '
                    '$offlineSnapshotCount منتج محفوظ لهذا الحساب '
                    '(الحد الأقصى ${CatalogRepository.offlineSnapshotLimit}). '
                    'لا تعتمد عليها لتأكيد آخر تعديل قبل عودة الاتصال.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (initialLoading)
              const Center(child: CircularProgressIndicator())
            else if (loadError != null)
              _ProductLoadError(
                onRetry: () =>
                    unawaited(_reloadProducts(refreshMetadata: true)),
              )
            else if (products.isEmpty)
              Card(
                key: const ValueKey('admin-products-empty-state'),
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('لا توجد منتجات بهذه الخيارات'),
                  subtitle: _activeFilterCount == 0
                      ? const Text('غيّر البحث أو حدّث قاعدة البيانات.')
                      : const Text('جرّب إزالة بعض الفلاتر لعرض نتائج أكثر.'),
                  trailing: _activeFilterCount == 0
                      ? null
                      : TextButton(
                          key: const ValueKey(
                            'admin-products-empty-clear-filters',
                          ),
                          onPressed: _clearProductFilters,
                          child: const Text('مسح'),
                        ),
                ),
              )
            else
              _buildProductCollection(context),
            if (!initialLoading && loadError == null && hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                child: FilledButton.tonalIcon(
                  key: const ValueKey('admin-products-load-more'),
                  onPressed: loadingMore ? null : _loadMoreProducts,
                  icon: loadingMore
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: Text(
                    loadingMore
                        ? 'جارٍ تحميل منتجات إضافية...'
                        : 'تحميل المزيد بنفس الفلاتر والترتيب',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  int get _activeFilterCount => [
        category,
        brand,
        animalType,
        unitSize,
        minimumPrice,
        maximumPrice,
        availability == 'all' ? null : availability,
      ].where((value) => value != null).length;

  List<_AdminProductFilterChipData> _activeFilterChips() {
    return [
      if (category != null)
        _AdminProductFilterChipData(
          label: 'التصنيف: $category',
          onDeleted: () => _removeProductFilter(() => category = null),
        ),
      if (brand != null)
        _AdminProductFilterChipData(
          label: 'الشركة: $brand',
          onDeleted: () => _removeProductFilter(() => brand = null),
        ),
      if (animalType != null)
        _AdminProductFilterChipData(
          label: 'النوع: $animalType',
          onDeleted: () => _removeProductFilter(() => animalType = null),
        ),
      if (unitSize != null)
        _AdminProductFilterChipData(
          label: 'العبوة: $unitSize',
          onDeleted: () => _removeProductFilter(() => unitSize = null),
        ),
      if (availability != 'all')
        _AdminProductFilterChipData(
          label: 'المخزون: ${_availabilityLabel(availability)}',
          onDeleted: () => _removeProductFilter(() => availability = 'all'),
        ),
      if (minimumPrice != null)
        _AdminProductFilterChipData(
          label: 'السعر من ${lyd(minimumPrice!)}',
          onDeleted: () => _removeProductFilter(() => minimumPrice = null),
        ),
      if (maximumPrice != null)
        _AdminProductFilterChipData(
          label: 'السعر إلى ${lyd(maximumPrice!)}',
          onDeleted: () => _removeProductFilter(() => maximumPrice = null),
        ),
    ];
  }

  void _removeProductFilter(VoidCallback change) {
    setState(change);
    unawaited(_reloadProducts());
  }

  void _clearProductFilters() {
    if (_activeFilterCount == 0) return;
    setState(() {
      category = null;
      brand = null;
      animalType = null;
      unitSize = null;
      minimumPrice = null;
      maximumPrice = null;
      availability = 'all';
    });
    unawaited(_reloadProducts());
  }

  void _selectSort(_AdminProductSort value) {
    if (sort == value) return;
    setState(() => sort = value);
    unawaited(_reloadProducts());
  }

  Future<void> _showProductFilters() async {
    final selected = await showModalBottomSheet<_AdminProductFilterSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AdminProductFiltersSheet(
        categories: categories,
        brands: brands,
        animalTypes: animalTypes,
        unitSizes: unitSizes,
        initial: _AdminProductFilterSelection(
          category: category,
          brand: brand,
          animalType: animalType,
          unitSize: unitSize,
          availability: availability,
          minimumPrice: minimumPrice,
          maximumPrice: maximumPrice,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      category = selected.category;
      brand = selected.brand;
      animalType = selected.animalType;
      unitSize = selected.unitSize;
      availability = selected.availability;
      minimumPrice = selected.minimumPrice;
      maximumPrice = selected.maximumPrice;
    });
    await _reloadProducts();
  }

  Widget _buildProductCollection(BuildContext context) {
    Future<void> onSelected(Product product, String value) =>
        _handleProductAction(product, value);
    return switch (viewMode) {
      _AdminProductViewMode.detailed => Column(
          key: const ValueKey('admin-products-results'),
          children: [
            for (final product in products)
              Card(
                key: ValueKey('admin-product-card-${product.id}'),
                child: _AdminProductCard(
                  product: product,
                  onSelected: (value) => onSelected(product, value),
                ),
              ),
          ],
        ),
      _AdminProductViewMode.compact => Column(
          key: const ValueKey('admin-products-results'),
          children: [
            for (final product in products)
              Card(
                key: ValueKey('admin-product-card-${product.id}'),
                child: _AdminProductCompactRow(
                  key: ValueKey('admin-product-compact-${product.id}'),
                  product: product,
                  onTap: () => _showProductForm(product),
                  onSelected: (value) => onSelected(product, value),
                ),
              ),
          ],
        ),
      _AdminProductViewMode.grid => LayoutBuilder(
          key: const ValueKey('admin-products-results'),
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1180
                ? 4
                : width >= 850
                    ? 3
                    : 2;
            final childAspectRatio = width < 520 ? .82 : 1.32;
            return GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: products.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                final product = products[index];
                return Card(
                  key: ValueKey('admin-product-card-${product.id}'),
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: _AdminProductGridTile(
                    key: ValueKey('admin-product-grid-${product.id}'),
                    product: product,
                    onTap: () => _showProductForm(product),
                    onSelected: (value) => onSelected(product, value),
                  ),
                );
              },
            );
          },
        ),
    };
  }

  Future<void> _handleProductAction(Product product, String value) async {
    if (value == 'edit') {
      await _showProductForm(product);
    } else if (value == 'archive') {
      await _archiveProduct(product);
    } else if (value == 'restore') {
      await _restoreProduct(product);
    }
  }

  void _selectCategory(String? value) {
    if (category == value) return;
    setState(() => category = value);
    unawaited(_reloadProducts());
  }

  Future<CatalogPage> _loadProductsPage({
    required String? categoryFilter,
    required String? brandFilter,
    required String? animalTypeFilter,
    required String? unitSizeFilter,
    required double? minimumPriceFilter,
    required double? maximumPriceFilter,
    required String availabilityFilter,
    required _AdminProductSort sortOrder,
    DateTime? pageSnapshot,
    int offset = 0,
  }) {
    final repository = ref.read(catalogRepositoryProvider);
    if (sortOrder == _AdminProductSort.newest) {
      return repository.productsPage(
        query: search.text,
        category: categoryFilter,
        brand: brandFilter,
        animalType: animalTypeFilter,
        unitSize: unitSizeFilter,
        minimumPrice: minimumPriceFilter,
        maximumPrice: maximumPriceFilter,
        availability: availabilityFilter,
        includeInactive: true,
        snapshotAt: pageSnapshot,
        offset: offset,
        pageSize: _pageSize,
      );
    }
    return repository.productsPageSorted(
      query: search.text,
      category: categoryFilter,
      brand: brandFilter,
      animalType: animalTypeFilter,
      unitSize: unitSizeFilter,
      minimumPrice: minimumPriceFilter,
      maximumPrice: maximumPriceFilter,
      availability: availabilityFilter,
      includeInactive: true,
      sort: sortOrder.queryValue,
      snapshotAt: pageSnapshot,
      offset: offset,
      pageSize: _pageSize,
    );
  }

  Future<void> _reloadProducts({bool refreshMetadata = false}) async {
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
    final shouldLoadMetadata = refreshMetadata || !metadataLoaded;
    try {
      final options =
          shouldLoadMetadata ? await _loadAdminFilterOptionsSafely() : null;
      if (!mounted || revision != loadRevision) return;
      var resolvedCategory = category;
      var resolvedBrand = brand;
      var resolvedAnimalType = animalType;
      var resolvedUnitSize = unitSize;
      if (refreshMetadata && options != null) {
        if (resolvedCategory != null &&
            !options.categories.contains(resolvedCategory)) {
          resolvedCategory = null;
        }
        if (resolvedBrand != null && !options.brands.contains(resolvedBrand)) {
          resolvedBrand = null;
        }
        if (resolvedAnimalType != null &&
            !options.animalTypes.contains(resolvedAnimalType)) {
          resolvedAnimalType = null;
        }
        if (resolvedUnitSize != null &&
            !options.unitSizes.contains(resolvedUnitSize)) {
          resolvedUnitSize = null;
        }
      }
      final page = await _loadProductsPage(
        categoryFilter: resolvedCategory,
        brandFilter: resolvedBrand,
        animalTypeFilter: resolvedAnimalType,
        unitSizeFilter: resolvedUnitSize,
        minimumPriceFilter: minimumPrice,
        maximumPriceFilter: maximumPrice,
        availabilityFilter: availability,
        sortOrder: sort,
      );
      if (!mounted || revision != loadRevision) return;
      setState(() {
        category = resolvedCategory;
        brand = resolvedBrand;
        animalType = resolvedAnimalType;
        unitSize = resolvedUnitSize;
        products = page.products
            .where(
              (product) =>
                  !product.isArchived || product.archivedByCategoryId == null,
            )
            .toList(growable: false);
        hasMore = page.hasMore;
        nextOffset = page.nextOffset;
        snapshotAt = page.snapshotAt;
        pageSource = page.source;
        offlineSnapshotCount = page.offlineSnapshotCount;
        if (options != null) {
          categories = _withSelectedCategory(
            options.categories,
            category,
          );
          brands = options.brands;
          animalTypes = options.animalTypes;
          unitSizes = options.unitSizes;
          metadataLoaded = true;
        }
        initialLoading = false;
      });
    } catch (error) {
      if (!mounted || revision != loadRevision) return;
      setState(() {
        loadError = error;
        initialLoading = false;
      });
    }
  }

  Future<CatalogFilterOptions?> _loadAdminFilterOptionsSafely() async {
    try {
      return await ref
          .read(catalogRepositoryProvider)
          .filterOptions(includeInactive: true);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMoreProducts() async {
    final pageSnapshot = snapshotAt;
    if (loadingMore || !hasMore || pageSnapshot == null) return;
    final revision = loadRevision;
    setState(() => loadingMore = true);
    try {
      final page = await _loadProductsPage(
        categoryFilter: category,
        brandFilter: brand,
        animalTypeFilter: animalType,
        unitSizeFilter: unitSize,
        minimumPriceFilter: minimumPrice,
        maximumPriceFilter: maximumPrice,
        availabilityFilter: availability,
        sortOrder: sort,
        pageSnapshot: pageSnapshot,
        offset: nextOffset,
      );
      if (!mounted || revision != loadRevision) return;
      setState(() {
        products = _deduplicateAdminProducts([
          ...products,
          ...page.products.where(
            (product) =>
                !product.isArchived || product.archivedByCategoryId == null,
          ),
        ]);
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

  Future<void> _createCategory() async {
    final created = await _promptAndCreateCategory();
    if (created == null || !mounted) return;
    await _reloadProducts(refreshMetadata: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إنشاء تصنيف «${created.name}».')),
    );
  }

  Future<ProductCategory?> _promptAndCreateCategory() async {
    final controller = TextEditingController();
    String? validationMessage;
    final navigator = Navigator.of(context, rootNavigator: true);
    final capturedThemes = InheritedTheme.capture(
      from: context,
      to: navigator.context,
    );
    final dialogRoute = DialogRoute<String>(
      context: context,
      themes: capturedThemes,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إنشاء تصنيف جديد'),
          content: SizedBox(
            width: 420,
            child: TextField(
              key: const ValueKey('new-category-name-field'),
              controller: controller,
              autofocus: true,
              maxLength: 120,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(
                    () => validationMessage = 'أدخل اسم التصنيف.',
                  );
                  return;
                }
                Navigator.pop(context, value);
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.category_outlined),
                labelText: 'اسم التصنيف',
                helperText: 'سيظهر في اختيار التصنيف عند إضافة المنتجات.',
                errorText: validationMessage,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              key: const ValueKey('save-category-button'),
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(
                    () => validationMessage = 'أدخل اسم التصنيف.',
                  );
                  return;
                }
                Navigator.pop(context, value);
              },
              icon: const Icon(Icons.add),
              label: const Text('إنشاء التصنيف'),
            ),
          ],
        ),
      ),
    );
    final name = await navigator.push(dialogRoute);
    await dialogRoute.completed;
    controller.dispose();
    if (name == null || !mounted) return null;
    try {
      return await ref.read(catalogRepositoryProvider).createCategory(name);
    } on CategoryArchivedException {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يوجد تصنيف مؤرشف بهذا الاسم. استعده من قسم «الأرشيف».',
          ),
        ),
      );
      return null;
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر إنشاء التصنيف. تحقق من الاسم والاتصال وحاول مجدداً.',
          ),
        ),
      );
      return null;
    }
  }

  Future<void> _showCategoryManager() async {
    final repository = ref.read(catalogRepositoryProvider);
    late List<ProductCategory> managedCategories;
    try {
      managedCategories = await repository.productCategories();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر تحميل التصنيفات. تحقق من الاتصال وحاول مجدداً.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    String? busyCategoryId;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.settings_outlined),
              SizedBox(width: 8),
              Expanded(child: Text('إدارة التصنيفات')),
            ],
          ),
          content: SizedBox(
            width: 560,
            height: 430,
            child: managedCategories.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.category_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'لا توجد تصنيفات نشطة',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: managedCategories.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = managedCategories[index];
                      final busy = busyCategoryId == item.id;
                      return ListTile(
                        key: ValueKey('managed-category-${item.id}'),
                        leading: CircleAvatar(
                          backgroundColor:
                              AppTheme.green.withValues(alpha: .12),
                          foregroundColor: AppTheme.green,
                          child: const Icon(Icons.category_outlined),
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          item.productCount == 0
                              ? 'لا توجد منتجات مرتبطة'
                              : '${item.productCount} منتج مرتبط',
                        ),
                        trailing: busy
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                key: ValueKey(
                                  'archive-category-${item.id}',
                                ),
                                tooltip: 'أرشفة التصنيف ومنتجاته',
                                onPressed: () async {
                                  final confirmed =
                                      await _confirmCategoryArchive(item);
                                  if (!confirmed ||
                                      !mounted ||
                                      !dialogContext.mounted) {
                                    return;
                                  }
                                  setDialogState(
                                    () => busyCategoryId = item.id,
                                  );
                                  try {
                                    await repository.archiveCategory(item.id);
                                  } catch (_) {
                                    if (!mounted || !dialogContext.mounted) {
                                      return;
                                    }
                                    setDialogState(
                                      () => busyCategoryId = null,
                                    );
                                    ScaffoldMessenger.of(this.context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'تعذر أرشفة التصنيف. '
                                          'تحقق من الاتصال وحاول مجدداً.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  var categoryRefreshFailed = false;
                                  try {
                                    managedCategories =
                                        await repository.productCategories();
                                  } catch (_) {
                                    categoryRefreshFailed = true;
                                    managedCategories = managedCategories
                                        .where(
                                          (category) => category.id != item.id,
                                        )
                                        .toList(growable: false);
                                  }
                                  if (!mounted || !dialogContext.mounted) {
                                    return;
                                  }
                                  if (category == item.name) {
                                    setState(() => category = null);
                                  }
                                  setDialogState(
                                    () => busyCategoryId = null,
                                  );
                                  await _reloadProducts(
                                    refreshMetadata: true,
                                  );
                                  if (!mounted) return;
                                  final refreshNotice = categoryRefreshFailed
                                      ? ' تمت الأرشفة، لكن تعذر تحديث قائمة '
                                          'التصنيفات بالكامل الآن.'
                                      : '';
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'تمت أرشفة «${item.name}» ومنتجاته. '
                                        'يمكنك استعادتها من الأرشيف.'
                                        '$refreshNotice',
                                      ),
                                    ),
                                  );
                                },
                                icon: Icon(
                                  Icons.archive_outlined,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: busyCategoryId == null
                  ? () => Navigator.pop(dialogContext)
                  : null,
              child: const Text('إغلاق'),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('manager-create-category-button'),
              onPressed: busyCategoryId != null
                  ? null
                  : () async {
                      final created = await _promptAndCreateCategory();
                      if (created == null ||
                          !mounted ||
                          !dialogContext.mounted) {
                        return;
                      }
                      var categoryRefreshFailed = false;
                      try {
                        managedCategories =
                            await repository.productCategories();
                      } catch (_) {
                        categoryRefreshFailed = true;
                        managedCategories = _withManagedCategory(
                          managedCategories,
                          created,
                        );
                      }
                      if (!dialogContext.mounted) return;
                      setDialogState(() {});
                      await _reloadProducts(refreshMetadata: true);
                      if (!mounted) return;
                      final refreshNotice = categoryRefreshFailed
                          ? ' تم الإنشاء، لكن تعذر تحديث قائمة التصنيفات '
                              'بالكامل الآن.'
                          : '';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'تم إنشاء تصنيف «${created.name}».'
                            '$refreshNotice',
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('تصنيف جديد'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmCategoryArchive(ProductCategory category) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد أرشفة التصنيف'),
            content: Text(
              'ستتم أرشفة «${category.name}» وكل المنتجات التابعة له '
              '(${category.productCount}). لن تظهر للعملاء، وستبقى البيانات '
              'والطلبات محفوظة ويمكن استعادتها من قسم «الأرشيف».',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                key: const ValueKey('confirm-archive-category-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('أرشفة التصنيف ومنتجاته'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showProductForm([Product? product]) async {
    final editing = product != null;
    final draftUuid = const Uuid().v4();
    var selectedCategory = product?.category ?? '';
    final categoryOptions = _withSelectedCategory(
      categories,
      product?.category,
    );
    final name = TextEditingController(text: product?.nameAr ?? '');
    final company = TextEditingController(text: product?.brand ?? '');
    final price = TextEditingController(
        text: product?.basePrice.toStringAsFixed(2) ?? '');
    final retailPrice = TextEditingController(
        text: product?.retailUnitPrice?.toStringAsFixed(2) ?? '');
    final bulkMinimum =
        TextEditingController(text: product?.minOrderQty.toString() ?? '1');
    final stock = TextEditingController(
      text: product?.stockQuantity.toString() ?? '',
    );
    final unitsPerBox =
        TextEditingController(text: product?.unitsPerBox?.toString() ?? '');
    final scrollController = ScrollController();
    var stockTrackingEnabled = product?.stockTrackingEnabled ?? true;
    var showStockQuantityToCustomers =
        product?.showStockQuantityToCustomers ?? false;
    var active =
        product?.isArchived == true ? false : product?.isActive ?? true;
    var hideWhenOutOfStock = product?.hideWhenOutOfStock ?? false;
    var fieldErrors = <_ProductFormField, String>{};
    final reservedQuantity = product?.reservedQuantity ?? 0;
    final nameFocus = FocusNode();
    final companyFocus = FocusNode();
    final priceFocus = FocusNode();
    final retailPriceFocus = FocusNode();
    final bulkMinimumFocus = FocusNode();
    final unitsPerBoxFocus = FocusNode();
    final stockFocus = FocusNode();
    FocusNode? categoryFocus;
    final nameKey = GlobalKey();
    final categoryKey = GlobalKey();
    final companyKey = GlobalKey();
    final priceKey = GlobalKey();
    final retailPriceKey = GlobalKey();
    final bulkMinimumKey = GlobalKey();
    final unitsPerBoxKey = GlobalKey();
    final stockKey = GlobalKey();
    final trackingKey = GlobalKey();

    void revealFirstInvalidField(Map<_ProductFormField, String> errors) {
      final first = _ProductFormField.values.firstWhere(errors.containsKey);
      final anchors = <_ProductFormField, GlobalKey>{
        _ProductFormField.name: nameKey,
        _ProductFormField.category: categoryKey,
        _ProductFormField.company: companyKey,
        _ProductFormField.price: priceKey,
        _ProductFormField.retailPrice: retailPriceKey,
        _ProductFormField.bulkMinimum: bulkMinimumKey,
        _ProductFormField.unitsPerBox: unitsPerBoxKey,
        _ProductFormField.stock: stockKey,
        _ProductFormField.tracking: trackingKey,
      };
      final focuses = <_ProductFormField, FocusNode?>{
        _ProductFormField.name: nameFocus,
        _ProductFormField.category: categoryFocus,
        _ProductFormField.company: companyFocus,
        _ProductFormField.price: priceFocus,
        _ProductFormField.retailPrice: retailPriceFocus,
        _ProductFormField.bulkMinimum: bulkMinimumFocus,
        _ProductFormField.unitsPerBox: unitsPerBoxFocus,
        _ProductFormField.stock: stockFocus,
        _ProductFormField.tracking: null,
      };
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _revealInvalidFormField(anchors[first]!, focuses[first]);
      });
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    final capturedThemes = InheritedTheme.capture(
      from: context,
      to: navigator.context,
    );
    final dialogRoute = DialogRoute<Product>(
      context: context,
      themes: capturedThemes,
      barrierColor: DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(editing ? 'تعديل المنتج' : 'منتج جديد'),
              const SizedBox(height: 6),
              const Row(
                key: ValueKey('product-form-scroll-hint'),
                children: [
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppTheme.green,
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'مرّر لأسفل لعرض بقية الحقول والخيارات',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: ScrollbarTheme(
              data: ScrollbarThemeData(
                thumbColor: WidgetStateProperty.all(AppTheme.green),
                trackColor: WidgetStateProperty.all(
                  AppTheme.green.withValues(alpha: 0.10),
                ),
                trackBorderColor: WidgetStateProperty.all(
                  AppTheme.green.withValues(alpha: 0.18),
                ),
                radius: const Radius.circular(999),
                thickness: WidgetStateProperty.all(8),
              ),
              child: Scrollbar(
                key: const ValueKey('product-form-scrollbar'),
                controller: scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: true,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                  ),
                  child: SingleChildScrollView(
                    key: const ValueKey('product-form-scroll-view'),
                    controller: scrollController,
                    padding: const EdgeInsetsDirectional.only(end: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(
                          key: nameKey,
                          child: TextField(
                            key: const ValueKey('product-name-field'),
                            controller: name,
                            focusNode: nameFocus,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setDialogState(() {
                              fieldErrors.remove(_ProductFormField.name);
                            }),
                            decoration: InputDecoration(
                              labelText: 'اسم المنتج',
                              errorText: fieldErrors[_ProductFormField.name],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Autocomplete<String>(
                          initialValue:
                              TextEditingValue(text: selectedCategory),
                          optionsMaxHeight: 220,
                          optionsBuilder: (value) {
                            final query = value.text.trim().toLowerCase();
                            if (query.isEmpty) return categoryOptions;
                            return categoryOptions.where(
                              (option) => option.toLowerCase().contains(query),
                            );
                          },
                          onSelected: (value) {
                            selectedCategory = value;
                            setDialogState(() {
                              fieldErrors.remove(_ProductFormField.category);
                            });
                          },
                          fieldViewBuilder: (
                            context,
                            controller,
                            focusNode,
                            onFieldSubmitted,
                          ) {
                            categoryFocus = focusNode;
                            return KeyedSubtree(
                              key: categoryKey,
                              child: TextField(
                                key: const ValueKey('product-category-field'),
                                controller: controller,
                                focusNode: focusNode,
                                textInputAction: TextInputAction.next,
                                onChanged: (value) {
                                  selectedCategory = value;
                                  setDialogState(() {
                                    fieldErrors
                                        .remove(_ProductFormField.category);
                                  });
                                },
                                onSubmitted: (_) => onFieldSubmitted(),
                                decoration: InputDecoration(
                                  prefixIcon:
                                      const Icon(Icons.category_outlined),
                                  labelText: 'التصنيف',
                                  helperText:
                                      'اختر تصنيفاً موجوداً أو اكتب اسماً جديداً؛ '
                                      'سيُنشأ عند الحفظ.',
                                  helperMaxLines: 2,
                                  errorText:
                                      fieldErrors[_ProductFormField.category],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        KeyedSubtree(
                          key: companyKey,
                          child: TextField(
                            key: const ValueKey('product-company-field'),
                            controller: company,
                            focusNode: companyFocus,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setDialogState(() {
                              fieldErrors.remove(_ProductFormField.company);
                            }),
                            decoration: InputDecoration(
                              labelText: 'اسم الشركة',
                              errorText: fieldErrors[_ProductFormField.company],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ResponsiveFieldGroup(
                          children: [
                            KeyedSubtree(
                              key: priceKey,
                              child: TextField(
                                key: const ValueKey('product-price-field'),
                                controller: price,
                                focusNode: priceFocus,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) => setDialogState(() {
                                  fieldErrors.remove(_ProductFormField.price);
                                }),
                                decoration: InputDecoration(
                                  labelText: 'سعر الجملة (د.ل)',
                                  helperText:
                                      'هذا هو السعر المستخدم في الطلب.',
                                  errorText:
                                      fieldErrors[_ProductFormField.price],
                                ),
                              ),
                            ),
                            KeyedSubtree(
                              key: retailPriceKey,
                              child: TextField(
                                key: const ValueKey(
                                  'product-retail-price-field',
                                ),
                                controller: retailPrice,
                                focusNode: retailPriceFocus,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) => setDialogState(() {
                                  fieldErrors
                                      .remove(_ProductFormField.retailPrice);
                                }),
                                decoration: InputDecoration(
                                  labelText: 'سعر بيع الوحدة المقترح (د.ل)',
                                  helperText:
                                      'مرجع للتاجر فقط ولا يدخل في الإجمالي.',
                                  errorText: fieldErrors[
                                      _ProductFormField.retailPrice],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ResponsiveFieldGroup(
                          children: [
                            KeyedSubtree(
                              key: bulkMinimumKey,
                              child: TextField(
                                key: const ValueKey(
                                  'product-bulk-minimum-field',
                                ),
                                controller: bulkMinimum,
                                focusNode: bulkMinimumFocus,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setDialogState(() {
                                  fieldErrors
                                      .remove(_ProductFormField.bulkMinimum);
                                }),
                                decoration: InputDecoration(
                                  labelText: 'الحد الأدنى لطلب الجملة',
                                  helperText: 'لا يمكن للعميل طلب كمية أقل.',
                                  errorText: fieldErrors[
                                      _ProductFormField.bulkMinimum],
                                ),
                              ),
                            ),
                            KeyedSubtree(
                              key: unitsPerBoxKey,
                              child: TextField(
                                key: const ValueKey(
                                  'product-units-per-box-field',
                                ),
                                controller: unitsPerBox,
                                focusNode: unitsPerBoxFocus,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setDialogState(() {
                                  fieldErrors
                                      .remove(_ProductFormField.unitsPerBox);
                                }),
                                decoration: InputDecoration(
                                  labelText: 'الكمية في الصندوق (اختياري)',
                                  helperText:
                                      'مثال: 12. لن تظهر إذا تركتها فارغة.',
                                  errorText: fieldErrors[
                                      _ProductFormField.unitsPerBox],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        KeyedSubtree(
                          key: trackingKey,
                          child: SwitchListTile.adaptive(
                            key: const ValueKey('product-track-stock-switch'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('تقييد الطلب حسب المخزون'),
                            subtitle: Text(
                              fieldErrors[_ProductFormField.tracking] ??
                                  'عند إيقافه يبقى العدد مسجلاً داخلياً، '
                                      'لكن يمكن الطلب دون حد مخزني.',
                              style: fieldErrors[_ProductFormField.tracking] ==
                                      null
                                  ? null
                                  : TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                      fontWeight: FontWeight.w700,
                                    ),
                            ),
                            value: stockTrackingEnabled,
                            onChanged: (value) => setDialogState(() {
                              stockTrackingEnabled = value;
                              if (!value) {
                                showStockQuantityToCustomers = false;
                              }
                              fieldErrors.remove(_ProductFormField.tracking);
                            }),
                          ),
                        ),
                        const SizedBox(height: 4),
                        KeyedSubtree(
                          key: stockKey,
                          child: TextField(
                            key: const ValueKey('product-stock-field'),
                            controller: stock,
                            focusNode: stockFocus,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setDialogState(() {
                              fieldErrors.remove(_ProductFormField.stock);
                            }),
                            decoration: InputDecoration(
                              labelText: 'كمية المخزون الداخلية (مطلوبة)',
                              helperText: reservedQuantity > 0
                                  ? 'منها $reservedQuantity محجوزة لطلبات قائمة.'
                                  : 'تُستخدم لإدارة المخزون حتى لو أخفيت العدد عن العملاء.',
                              errorText: fieldErrors[_ProductFormField.stock],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile.adaptive(
                          key: const ValueKey(
                            'product-show-stock-quantity-switch',
                          ),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('إظهار الكمية الدقيقة للعملاء'),
                          subtitle: Text(
                            !stockTrackingEnabled
                                ? 'فعّل تقييد الطلب حسب المخزون أولاً.'
                                : showStockQuantityToCustomers
                                    ? 'سيظهر العدد المتاح في الكتالوج والتفاصيل.'
                                    : 'سيظهر «متوفر للطلب» دون كشف العدد.',
                          ),
                          value: stockTrackingEnabled &&
                              showStockQuantityToCustomers,
                          onChanged: stockTrackingEnabled
                              ? (value) => setDialogState(() {
                                    showStockQuantityToCustomers = value;
                                  })
                              : null,
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          key: const ValueKey('product-visible-switch'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('إظهار المنتج للعملاء'),
                          subtitle: Text(
                            product?.isArchived == true
                                ? 'المنتج مؤرشف. استخدم «استعادة ونشر المنتج» من القائمة أولاً.'
                                : active
                                    ? 'المنتج ظاهر في المتجر.'
                                    : 'المنتج مخفي عن العملاء دون حذفه.',
                          ),
                          value: active,
                          onChanged: product?.isArchived == true
                              ? null
                              : (value) => setDialogState(() {
                                    active = value;
                                  }),
                        ),
                        if (stockTrackingEnabled) ...[
                          const SizedBox(height: 4),
                          SwitchListTile.adaptive(
                            key: const ValueKey(
                              'product-hide-when-out-of-stock-switch',
                            ),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('إخفاء المنتج عند نفاد المخزون'),
                            subtitle: Text(
                              hideWhenOutOfStock
                                  ? 'سيختفي من المتجر عندما لا تكفي الكمية للطلب.'
                                  : 'سيبقى ظاهراً مع عبارة «غير متوفر حالياً».',
                            ),
                            value: hideWhenOutOfStock,
                            onChanged: (value) => setDialogState(() {
                              hideWhenOutOfStock = value;
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final parsedPrice = _parseLocalizedDouble(price.text);
                final parsedRetailPrice =
                    _parseLocalizedDouble(retailPrice.text);
                final parsedBulkMinimum = _parseLocalizedInt(bulkMinimum.text);
                final parsedStock = _parseLocalizedInt(stock.text);
                final parsedUnitsPerBox = unitsPerBox.text.trim().isEmpty
                    ? null
                    : _parseLocalizedInt(unitsPerBox.text);
                final errors = <_ProductFormField, String>{};
                if (name.text.trim().isEmpty) {
                  errors[_ProductFormField.name] = 'أدخل اسم المنتج.';
                }
                if (selectedCategory.trim().isEmpty) {
                  errors[_ProductFormField.category] =
                      'اختر تصنيفاً أو اكتب اسم تصنيف جديد.';
                }
                if (company.text.trim().isEmpty) {
                  errors[_ProductFormField.company] = 'أدخل اسم الشركة.';
                }
                if (parsedPrice == null ||
                    !parsedPrice.isFinite ||
                    parsedPrice <= 0) {
                  errors[_ProductFormField.price] =
                      'أدخل سعر جملة صحيحاً أكبر من صفر.';
                }
                if (parsedRetailPrice == null ||
                    !parsedRetailPrice.isFinite ||
                    parsedRetailPrice <= 0) {
                  errors[_ProductFormField.retailPrice] =
                      'أدخل سعر بيع وحدة مقترحاً صحيحاً أكبر من صفر.';
                }
                if (parsedBulkMinimum == null ||
                    parsedBulkMinimum < 1 ||
                    parsedBulkMinimum > 1000000) {
                  errors[_ProductFormField.bulkMinimum] =
                      'الحد الأدنى لطلب الجملة يجب أن يكون رقماً صحيحاً موجباً.';
                }
                if (parsedUnitsPerBox != null &&
                    (parsedUnitsPerBox < 1 || parsedUnitsPerBox > 1000000)) {
                  errors[_ProductFormField.unitsPerBox] =
                      'الكمية في الصندوق يجب أن تكون رقماً صحيحاً موجباً.';
                }
                if (parsedStock == null || parsedStock < 0) {
                  errors[_ProductFormField.stock] =
                      'أدخل كمية مخزون صحيحة لا تقل عن صفر.';
                } else if (stockTrackingEnabled &&
                    parsedStock < reservedQuantity) {
                  errors[_ProductFormField.stock] =
                      'لا يمكن خفض المخزون عن الكمية المحجوزة ($reservedQuantity).';
                }
                if (!stockTrackingEnabled && reservedQuantity > 0) {
                  errors[_ProductFormField.tracking] =
                      'لا يمكن إيقاف تتبع المخزون مع وجود $reservedQuantity قطعة محجوزة.';
                }
                if (errors.isNotEmpty) {
                  setDialogState(() => fieldErrors = errors);
                  revealFirstInvalidField(errors);
                  return;
                }

                final resolvedCategory = selectedCategory.trim();
                final resolvedStock = parsedStock!;
                final internalSku = product?.sku.trim().isNotEmpty == true
                    ? product!.sku.trim()
                    : 'AUTO-${draftUuid.replaceAll('-', '').substring(0, 12).toUpperCase()}';
                Navigator.pop(
                  context,
                  Product(
                    id: product?.id ?? 'local-$draftUuid',
                    nameAr: name.text.trim(),
                    nameEn: product?.nameEn,
                    sku: internalSku,
                    category: resolvedCategory,
                    categoryId: product?.category == resolvedCategory
                        ? product?.categoryId
                        : null,
                    animalType: product?.animalType ?? '',
                    brand: company.text.trim(),
                    unitSize: product?.unitSize ?? '',
                    packageSize: product?.packageSize,
                    basePrice: parsedPrice!,
                    effectivePrice: null,
                    retailUnitPrice: parsedRetailPrice,
                    oldPrice: product?.oldPrice,
                    discountPercent: product?.discountPercent,
                    stockQuantity: resolvedStock,
                    availableQuantity: stockTrackingEnabled && product != null
                        ? resolvedStock - reservedQuantity
                        : null,
                    stockTrackingEnabled: stockTrackingEnabled,
                    showStockQuantityToCustomers:
                        stockTrackingEnabled && showStockQuantityToCustomers,
                    hideWhenOutOfStock: hideWhenOutOfStock,
                    unitsPerBox: parsedUnitsPerBox,
                    minOrderQty: parsedBulkMinimum!,
                    descriptionAr: product?.descriptionAr ?? '',
                    imageUrl: product?.imageUrl,
                    imageAttribution: product?.imageAttribution,
                    sourceUrl: product?.sourceUrl,
                    isActive: active,
                    isFeatured: product?.isFeatured ?? false,
                    isTopSelling: product?.isTopSelling ?? false,
                    archivedAt: product?.archivedAt,
                    createdAt: product?.createdAt,
                    updatedAt: product?.updatedAt,
                    packageOptions: product?.packageOptions ?? const [],
                    tags: product?.tags ?? [company.text.trim()],
                  ),
                );
              },
              child: const Text('حفظ المنتج'),
            ),
          ],
        ),
      ),
    );
    final saved = await navigator.push(dialogRoute);
    await dialogRoute.completed;

    for (final controller in [
      name,
      company,
      price,
      retailPrice,
      bulkMinimum,
      stock,
      unitsPerBox,
    ]) {
      controller.dispose();
    }
    for (final focus in [
      nameFocus,
      companyFocus,
      priceFocus,
      retailPriceFocus,
      bulkMinimumFocus,
      unitsPerBoxFocus,
      stockFocus,
    ]) {
      focus.dispose();
    }
    scrollController.dispose();
    if (saved == null) return;
    try {
      await ref.read(catalogRepositoryProvider).saveProduct(saved);
      if (mounted) {
        await _reloadProducts(refreshMetadata: true);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('تعذر حفظ المنتج. تحقق من البيانات والاتصال وحاول مجدداً.'),
        ),
      );
    }
  }

  Future<void> _archiveProduct(Product product) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد أرشفة المنتج'),
            content: Text(
              'سيختفي «${product.name}» من كتالوج العملاء ولن يمكن طلبه. '
              'يمكن استعادته لاحقاً.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('أرشفة'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(catalogRepositoryProvider).archiveProduct(product.id);
      if (!mounted) return;
      await _reloadProducts(refreshMetadata: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر أرشفة المنتج. تحقق من الاتصال وحاول مجدداً.'),
        ),
      );
    }
  }

  Future<void> _restoreProduct(Product product) async {
    try {
      await ref.read(catalogRepositoryProvider).restoreProduct(product.id);
      if (!mounted) return;
      await _reloadProducts(refreshMetadata: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت استعادة المنتج ونشره للعملاء.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر استعادة المنتج. تحقق من الاتصال وحاول مجدداً.'),
        ),
      );
    }
  }
}

List<String> _withSelectedCategory(
  Iterable<String> values,
  String? selected,
) {
  final result = <String>{
    if (selected?.trim().isNotEmpty == true) selected!.trim(),
    for (final value in values)
      if (value.trim().isNotEmpty) value.trim(),
  }.toList()
    ..sort();
  return result;
}

List<ProductCategory> _withManagedCategory(
  Iterable<ProductCategory> values,
  ProductCategory added,
) {
  final result = <ProductCategory>[
    for (final category in values)
      if (category.id != added.id) category,
    added,
  ]..sort((first, second) => first.name.compareTo(second.name));
  return result;
}

List<Product> _deduplicateAdminProducts(Iterable<Product> source) {
  final seen = <String>{};
  return [
    for (final product in source)
      if (seen.add(product.id)) product,
  ];
}

String _normalizeLocalizedNumber(String value) {
  const easternArabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const westernArabicDigits = '0123456789';
  final buffer = StringBuffer();
  for (final rune in value.trim().runes) {
    final character = String.fromCharCode(rune);
    final digitIndex = easternArabicDigits.indexOf(character);
    if (digitIndex >= 0) {
      buffer.write(westernArabicDigits[digitIndex]);
    } else if (character == '٫' || character == '،' || character == ',') {
      buffer.write('.');
    } else {
      buffer.write(character);
    }
  }
  return buffer.toString();
}

enum _ProductFormField {
  name,
  category,
  company,
  price,
  retailPrice,
  bulkMinimum,
  unitsPerBox,
  stock,
  tracking,
}

void _revealInvalidFormField(GlobalKey key, FocusNode? focus) {
  final target = key.currentContext;
  if (target != null && target.mounted) {
    Scrollable.ensureVisible(
      target,
      alignment: 0.12,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }
  focus?.requestFocus();
}

double? _parseLocalizedDouble(String value) =>
    double.tryParse(_normalizeLocalizedNumber(value));

int? _parseLocalizedInt(String value) {
  final normalized = _normalizeLocalizedNumber(value);
  if (normalized.contains('.')) return null;
  return int.tryParse(normalized);
}

enum _AdminProductViewMode {
  detailed,
  compact,
  grid,
}

enum _AdminProductSort {
  newest('newest', 'الأحدث أولاً', Icons.schedule),
  oldest('oldest', 'الأقدم أولاً', Icons.history),
  nameAscending('name_asc', 'الاسم: أ–ي', Icons.sort_by_alpha),
  priceAscending('price_asc', 'السعر: الأقل أولاً', Icons.south),
  priceDescending('price_desc', 'السعر: الأعلى أولاً', Icons.north),
  stockAscending(
      'stock_asc', 'المخزون: الأقل أولاً', Icons.inventory_2_outlined),
  stockDescending(
    'stock_desc',
    'المخزون: الأعلى أولاً',
    Icons.inventory_2,
  );

  const _AdminProductSort(this.queryValue, this.label, this.icon);

  final String queryValue;
  final String label;
  final IconData icon;
}

String _availabilityLabel(String value) => switch (value) {
      'in_stock' => 'متاح للطلب',
      'low_stock' => 'منخفض',
      'out_of_stock' => 'غير متاح',
      _ => 'الكل',
    };

class _AdminProductFilterSelection {
  const _AdminProductFilterSelection({
    this.category,
    this.brand,
    this.animalType,
    this.unitSize,
    this.availability = 'all',
    this.minimumPrice,
    this.maximumPrice,
  });

  final String? category;
  final String? brand;
  final String? animalType;
  final String? unitSize;
  final String availability;
  final double? minimumPrice;
  final double? maximumPrice;
}

class _AdminProductFilterChipData {
  const _AdminProductFilterChipData({
    required this.label,
    required this.onDeleted,
  });

  final String label;
  final VoidCallback onDeleted;
}

class _AdminProductsBrowseToolbar extends StatelessWidget {
  const _AdminProductsBrowseToolbar({
    required this.viewMode,
    required this.sort,
    required this.activeFilterCount,
    required this.resultCount,
    required this.hasMore,
    required this.onViewModeChanged,
    required this.onSortChanged,
    required this.onOpenFilters,
    required this.onClearFilters,
  });

  final _AdminProductViewMode viewMode;
  final _AdminProductSort sort;
  final int activeFilterCount;
  final int resultCount;
  final bool hasMore;
  final ValueChanged<_AdminProductViewMode> onViewModeChanged;
  final ValueChanged<_AdminProductSort> onSortChanged;
  final VoidCallback onOpenFilters;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          key: const ValueKey('admin-products-view-selector'),
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('admin-products-filter-button'),
              onPressed: onOpenFilters,
              icon: Badge(
                isLabelVisible: activeFilterCount > 0,
                label: Text('$activeFilterCount'),
                child: const Icon(Icons.tune),
              ),
              label: const Text('فلترة'),
            ),
            PopupMenuButton<_AdminProductSort>(
              key: const ValueKey('admin-products-sort-button'),
              tooltip: 'ترتيب المنتجات',
              onSelected: onSortChanged,
              itemBuilder: (context) => [
                for (final option in _AdminProductSort.values)
                  PopupMenuItem(
                    key: ValueKey(
                      'admin-products-sort-${option.queryValue}',
                    ),
                    value: option,
                    child: Row(
                      children: [
                        Icon(option.icon, size: 19),
                        const SizedBox(width: 9),
                        Expanded(child: Text(option.label)),
                        if (option == sort)
                          Icon(
                            Icons.check,
                            color: colorScheme.primary,
                            size: 19,
                          ),
                      ],
                    ),
                  ),
              ],
              child: _AdminToolbarPill(
                icon: sort.icon,
                label: sort.label,
              ),
            ),
            _AdminProductViewSelector(
              viewMode: viewMode,
              onChanged: onViewModeChanged,
            ),
            Text(
              hasMore ? '$resultCount محمّل + المزيد' : '$resultCount منتج',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (onClearFilters != null)
              TextButton.icon(
                key: const ValueKey('clear-admin-product-filters'),
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('مسح الفلاتر'),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminToolbarPill extends StatelessWidget {
  const _AdminToolbarPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 10, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class _AdminProductViewSelector extends StatelessWidget {
  const _AdminProductViewSelector({
    required this.viewMode,
    required this.onChanged,
  });

  final _AdminProductViewMode viewMode;
  final ValueChanged<_AdminProductViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: .6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AdminProductViewButton(
            key: const ValueKey('admin-products-view-detailed'),
            icon: Icons.view_agenda_outlined,
            tooltip: 'عرض تفصيلي',
            selected: viewMode == _AdminProductViewMode.detailed,
            onPressed: () => onChanged(_AdminProductViewMode.detailed),
          ),
          _AdminProductViewButton(
            key: const ValueKey('admin-products-view-compact'),
            icon: Icons.view_list_outlined,
            tooltip: 'عرض مختصر',
            selected: viewMode == _AdminProductViewMode.compact,
            onPressed: () => onChanged(_AdminProductViewMode.compact),
          ),
          _AdminProductViewButton(
            key: const ValueKey('admin-products-view-grid'),
            icon: Icons.grid_view_outlined,
            tooltip: 'عرض شبكي',
            selected: viewMode == _AdminProductViewMode.grid,
            onPressed: () => onChanged(_AdminProductViewMode.grid),
          ),
        ],
      ),
    );
  }
}

class _AdminProductViewButton extends StatelessWidget {
  const _AdminProductViewButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      selectedIcon: Icon(icon),
      icon: Icon(icon),
      style: selected
          ? IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            )
          : null,
    );
  }
}

class _AdminProductActiveFilters extends StatelessWidget {
  const _AdminProductActiveFilters({
    required this.chips,
    required this.onClearAll,
  });

  final List<_AdminProductFilterChipData> chips;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('admin-products-active-filters'),
      spacing: 7,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final chip in chips)
          InputChip(
            label: Text(chip.label),
            onDeleted: chip.onDeleted,
            deleteIcon: const Icon(Icons.close, size: 17),
          ),
        TextButton(
          onPressed: onClearAll,
          child: const Text('مسح الكل'),
        ),
      ],
    );
  }
}

class _AdminProductFiltersSheet extends StatefulWidget {
  const _AdminProductFiltersSheet({
    required this.categories,
    required this.brands,
    required this.animalTypes,
    required this.unitSizes,
    required this.initial,
  });

  final List<String> categories;
  final List<String> brands;
  final List<String> animalTypes;
  final List<String> unitSizes;
  final _AdminProductFilterSelection initial;

  @override
  State<_AdminProductFiltersSheet> createState() =>
      _AdminProductFiltersSheetState();
}

class _AdminProductFiltersSheetState extends State<_AdminProductFiltersSheet> {
  late String? category = widget.initial.category;
  late String? brand = widget.initial.brand;
  late String? animalType = widget.initial.animalType;
  late String? unitSize = widget.initial.unitSize;
  late String availability = widget.initial.availability;
  late final TextEditingController minimumPrice = TextEditingController(
    text: widget.initial.minimumPrice?.toStringAsFixed(2) ?? '',
  );
  late final TextEditingController maximumPrice = TextEditingController(
    text: widget.initial.maximumPrice?.toStringAsFixed(2) ?? '',
  );
  String? validationMessage;

  @override
  void dispose() {
    minimumPrice.dispose();
    maximumPrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SizedBox(
        key: const ValueKey('admin-products-filter-sheet'),
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 10, 8),
              child: Row(
                children: [
                  const Icon(Icons.tune),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'فلترة المنتجات',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _AdminFilterDropdown(
                    key: const ValueKey('admin-products-filter-category'),
                    label: 'التصنيف',
                    allLabel: 'كل التصنيفات',
                    value: category,
                    values: _withSelectedFilterValue(
                      widget.categories,
                      category,
                    ),
                    onChanged: (value) => setState(() => category = value),
                  ),
                  const SizedBox(height: 10),
                  _AdminFilterDropdown(
                    key: const ValueKey('admin-products-filter-brand'),
                    label: 'الشركة / العلامة',
                    allLabel: 'كل الشركات',
                    value: brand,
                    values: _withSelectedFilterValue(widget.brands, brand),
                    onChanged: (value) => setState(() => brand = value),
                  ),
                  const SizedBox(height: 10),
                  _AdminFilterDropdown(
                    key: const ValueKey('admin-products-filter-animal-type'),
                    label: 'نوع الحيوان',
                    allLabel: 'كل الأنواع',
                    value: animalType,
                    values: _withSelectedFilterValue(
                      widget.animalTypes,
                      animalType,
                    ),
                    onChanged: (value) => setState(() => animalType = value),
                  ),
                  const SizedBox(height: 10),
                  _AdminFilterDropdown(
                    key: const ValueKey('admin-products-filter-unit-size'),
                    label: 'الحجم / العبوة',
                    allLabel: 'كل الأحجام',
                    value: unitSize,
                    values: _withSelectedFilterValue(
                      widget.unitSizes,
                      unitSize,
                    ),
                    onChanged: (value) => setState(() => unitSize = value),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: const ValueKey(
                      'admin-products-filter-availability',
                    ),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'admin-products-filter-availability-$availability',
                      ),
                      initialValue: availability,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'حالة المخزون'),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('كل حالات المخزون'),
                        ),
                        DropdownMenuItem(
                          value: 'in_stock',
                          child: Text('متاح للطلب'),
                        ),
                        DropdownMenuItem(
                          value: 'low_stock',
                          child: Text('مخزون منخفض'),
                        ),
                        DropdownMenuItem(
                          value: 'out_of_stock',
                          child: Text('غير متاح للطلب'),
                        ),
                      ],
                      onChanged: (value) => setState(
                        () => availability = value ?? 'all',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ResponsiveFieldGroup(
                    children: [
                      TextField(
                        key: const ValueKey(
                          'admin-products-filter-minimum-price',
                        ),
                        controller: minimumPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'أقل سعر جملة'),
                      ),
                      TextField(
                        key: const ValueKey(
                          'admin-products-filter-maximum-price',
                        ),
                        controller: maximumPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'أعلى سعر جملة'),
                      ),
                    ],
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      validationMessage!,
                      key: const ValueKey(
                        'admin-products-filter-validation',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey(
                        'admin-products-reset-filter-draft',
                      ),
                      onPressed: _reset,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('إعادة ضبط'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('admin-products-apply-filters'),
                      onPressed: _apply,
                      icon: const Icon(Icons.check),
                      label: const Text('تطبيق الفلاتر'),
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

  void _reset() {
    setState(() {
      category = null;
      brand = null;
      animalType = null;
      unitSize = null;
      availability = 'all';
      minimumPrice.clear();
      maximumPrice.clear();
      validationMessage = null;
    });
  }

  void _apply() {
    final minimumText = minimumPrice.text.trim();
    final maximumText = maximumPrice.text.trim();
    final parsedMinimum =
        minimumText.isEmpty ? null : _parseLocalizedDouble(minimumText);
    final parsedMaximum =
        maximumText.isEmpty ? null : _parseLocalizedDouble(maximumText);
    if ((minimumText.isNotEmpty &&
            (parsedMinimum == null ||
                !parsedMinimum.isFinite ||
                parsedMinimum < 0)) ||
        (maximumText.isNotEmpty &&
            (parsedMaximum == null ||
                !parsedMaximum.isFinite ||
                parsedMaximum < 0))) {
      setState(() {
        validationMessage = 'أدخل نطاق سعر صحيحاً لا يقل عن صفر.';
      });
      return;
    }
    if (parsedMinimum != null &&
        parsedMaximum != null &&
        parsedMinimum > parsedMaximum) {
      setState(() {
        validationMessage = 'أقل سعر يجب ألا يكون أكبر من أعلى سعر.';
      });
      return;
    }
    Navigator.pop(
      context,
      _AdminProductFilterSelection(
        category: category,
        brand: brand,
        animalType: animalType,
        unitSize: unitSize,
        availability: availability,
        minimumPrice: parsedMinimum,
        maximumPrice: parsedMaximum,
      ),
    );
  }
}

class _AdminFilterDropdown extends StatelessWidget {
  const _AdminFilterDropdown({
    required this.label,
    required this.allLabel,
    required this.value,
    required this.values,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String allLabel;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      key: ValueKey('$label-${value ?? 'all'}'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(value: null, child: Text(allLabel)),
        for (final option in values)
          DropdownMenuItem(value: option, child: Text(option)),
      ],
      onChanged: onChanged,
    );
  }
}

List<String> _withSelectedFilterValue(
  Iterable<String> values,
  String? selected,
) {
  return <String>{
    if (selected?.trim().isNotEmpty == true) selected!.trim(),
    for (final value in values)
      if (value.trim().isNotEmpty) value.trim(),
  }.toList()
    ..sort();
}

class _AdminProductCard extends StatelessWidget {
  const _AdminProductCard({
    required this.product,
    required this.onSelected,
  });

  final Product product;
  final Future<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    final visibilityLabel = product.isArchived
        ? 'مؤرشف'
        : product.active
            ? 'ظاهر للعملاء'
            : 'مخفي عن العملاء';
    final visibilityIcon = product.isArchived
        ? Icons.archive_outlined
        : product.active
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined;
    final visibilityColor = product.isArchived || !product.active
        ? Colors.blueGrey
        : AppTheme.green;
    final availabilityLabel = !product.stockTrackingEnabled
        ? 'المخزون غير متتبع'
        : !product.isOrderable
            ? 'غير متاح للطلب'
            : product.lowStock
                ? 'مخزون منخفض'
                : 'متاح للطلب';
    final availabilityColor = !product.stockTrackingEnabled
        ? Colors.blueGrey
        : !product.isOrderable
            ? AppTheme.red
            : product.lowStock
                ? AppTheme.orange
                : AppTheme.green;
    final quantityVisibilityLabel =
        product.stockTrackingEnabled && product.showStockQuantityToCustomers
            ? 'العدد للعملاء: ظاهر'
            : 'العدد للعملاء: مخفي';
    final accentColor = product.isArchived || !product.active
        ? Colors.blueGrey
        : availabilityColor;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: .13),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 20,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                    if (product.brand.trim().isNotEmpty)
                      Text(
                        product.brand,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ),
              _AdminProductMenu(
                product: product,
                onSelected: onSelected,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _AdminProductInfoPill(
                key: ValueKey('admin-product-publish-state-${product.id}'),
                icon: visibilityIcon,
                label: visibilityLabel,
                color: visibilityColor,
              ),
              _AdminProductInfoPill(
                key: ValueKey('admin-product-availability-${product.id}'),
                icon: product.stockTrackingEnabled
                    ? Icons.check_circle_outline
                    : Icons.sync_disabled_outlined,
                label: availabilityLabel,
                color: availabilityColor,
              ),
              _AdminProductInfoPill(
                key: ValueKey('admin-product-customer-quantity-${product.id}'),
                icon: product.stockTrackingEnabled &&
                        product.showStockQuantityToCustomers
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                label: quantityVisibilityLabel,
                color: product.stockTrackingEnabled &&
                        product.showStockQuantityToCustomers
                    ? AppTheme.green
                    : Colors.blueGrey,
              ),
              if (product.stockTrackingEnabled)
                _AdminProductInfoPill(
                  key: ValueKey(
                    'admin-product-out-of-stock-behavior-${product.id}',
                  ),
                  icon: product.hideWhenOutOfStock
                      ? Icons.hide_source_outlined
                      : Icons.public_outlined,
                  label: product.hideWhenOutOfStock
                      ? 'يختفي عند النفاد'
                      : 'يبقى ظاهراً عند النفاد',
                  color: Colors.blueGrey,
                ),
              if (product.unitsPerBox != null && product.unitsPerBox! > 0)
                _AdminProductInfoPill(
                  key: ValueKey('admin-product-box-units-${product.id}'),
                  icon: Icons.inventory_outlined,
                  label: '${product.unitsPerBox} في الصندوق',
                  color: Colors.blueGrey,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            key: ValueKey('admin-product-stock-${product.id}'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: .32),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              spacing: 14,
              runSpacing: 3,
              children: [
                _AdminProductMetric(
                  icon: Icons.inventory_2_outlined,
                  label: 'المخزون',
                  value: '${product.stockQuantity}',
                ),
                if (product.stockTrackingEnabled)
                  _AdminProductMetric(
                    icon: Icons.done_all,
                    label: 'المتاح',
                    value: '${product.orderableStockQuantity}',
                  ),
                if (product.reservedQuantity > 0)
                  _AdminProductMetric(
                    icon: Icons.lock_clock_outlined,
                    label: 'محجوز',
                    value: '${product.reservedQuantity}',
                  ),
                _AdminProductMetric(
                  key: ValueKey('admin-product-moq-${product.id}'),
                  icon: Icons.shopping_cart_checkout_outlined,
                  label: 'أقل طلب',
                  value: '${product.minOrderQty}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            key: ValueKey('admin-product-prices-${product.id}'),
            spacing: 16,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'سعر الجملة ${lyd(product.price)}',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.darkGreen,
                ),
              ),
              if (product.retailUnitPrice != null)
                Text(
                  'بيع الوحدة المقترح ${lyd(product.retailUnitPrice!)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminProductCompactRow extends StatelessWidget {
  const _AdminProductCompactRow({
    required this.product,
    required this.onTap,
    required this.onSelected,
    super.key,
  });

  final Product product;
  final VoidCallback onTap;
  final Future<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    final stateColor = _adminProductStateColor(product);
    return Semantics(
      button: true,
      label: 'فتح تعديل ${product.name}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: stateColor,
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (product.brand.trim().isNotEmpty) product.brand,
                        if (product.category.trim().isNotEmpty)
                          product.category,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        Text(
                          lyd(product.price),
                          style: const TextStyle(
                            color: AppTheme.darkGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          product.stockTrackingEnabled
                              ? 'المتاح ${product.orderableStockQuantity}'
                              : 'المخزون غير متتبع',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          _adminProductStateLabel(product),
                          style: TextStyle(
                            color: stateColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _AdminProductMenu(
                product: product,
                onSelected: onSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminProductGridTile extends StatelessWidget {
  const _AdminProductGridTile({
    required this.product,
    required this.onTap,
    required this.onSelected,
    super.key,
  });

  final Product product;
  final VoidCallback onTap;
  final Future<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    final stateColor = _adminProductStateColor(product);
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'فتح تعديل ${product.name}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductImagePlaceholder(
                    productId: product.id,
                    category: product.category,
                    imageUrl: product.imageUrl,
                    semanticLabel: 'صورة ${product.name}',
                    size: 52,
                  ),
                  const Spacer(),
                  _AdminProductMenu(
                    product: product,
                    onSelected: onSelected,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                product.brand.trim().isEmpty
                    ? product.category
                    : '${product.brand} • ${product.category}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                  fontSize: 10.5,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: stateColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _adminProductStateLabel(product),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: stateColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    product.stockTrackingEnabled
                        ? 'متاح ${product.orderableStockQuantity}'
                        : 'غير متتبع',
                    style: const TextStyle(fontSize: 10.5),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                lyd(product.price),
                style: textTheme.bodyMedium?.copyWith(
                  color: AppTheme.darkGreen,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminProductMenu extends StatelessWidget {
  const _AdminProductMenu({
    required this.product,
    required this.onSelected,
  });

  final Product product;
  final Future<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: ValueKey('admin-product-menu-${product.id}'),
      tooltip: 'خيارات المنتج',
      padding: EdgeInsets.zero,
      iconSize: 22,
      constraints: const BoxConstraints.tightFor(
        width: 40,
        height: 40,
      ),
      onSelected: (value) => unawaited(onSelected(value)),
      itemBuilder: (context) => [
        PopupMenuItem(
          key: ValueKey('admin-product-edit-${product.id}'),
          value: 'edit',
          child: const Text('تعديل'),
        ),
        if (product.isArchived)
          PopupMenuItem(
            key: ValueKey('admin-product-restore-${product.id}'),
            value: 'restore',
            child: const Text('استعادة ونشر المنتج'),
          )
        else
          PopupMenuItem(
            key: ValueKey('admin-product-archive-${product.id}'),
            value: 'archive',
            child: const Text('أرشفة المنتج'),
          ),
      ],
    );
  }
}

String _adminProductStateLabel(Product product) {
  if (product.isArchived) return 'مؤرشف';
  if (!product.active) return 'مخفي';
  if (!product.stockTrackingEnabled) return 'ظاهر • غير متتبع';
  if (!product.isOrderable) return 'غير متاح';
  if (product.lowStock) return 'مخزون منخفض';
  return 'ظاهر ومتاح';
}

Color _adminProductStateColor(Product product) {
  if (product.isArchived || !product.active) return Colors.blueGrey;
  if (!product.stockTrackingEnabled) return Colors.blueGrey;
  if (!product.isOrderable) return AppTheme.red;
  if (product.lowStock) return AppTheme.orange;
  return AppTheme.green;
}

class _AdminProductInfoPill extends StatelessWidget {
  const _AdminProductInfoPill({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminProductMetric extends StatelessWidget {
  const _AdminProductMetric({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$label '),
              TextSpan(
                text: value,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 11, height: 1.25),
        ),
      ],
    );
  }
}

class _ProductLoadError extends StatelessWidget {
  const _ProductLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 52),
            const SizedBox(height: 12),
            Text(
              'تعذر تحميل المنتجات',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text('تحقق من الاتصال ثم أعد المحاولة.'),
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
