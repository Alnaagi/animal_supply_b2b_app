import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/concurrency/stale_write.dart';
import '../../core/config/app_config.dart';
import '../../core/refresh/screen_reload.dart';
import '../../core/updates/update_link.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/category_icon_view.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/product_info_chip.dart';
import '../../core/widgets/responsive_field_group.dart';
import '../../core/widgets/shop_loading.dart';
import '../../core/widgets/shop_skeleton.dart';
import '../../core/widgets/shop_refresh_indicator.dart';
import '../../data/models/product.dart';
import '../../data/models/product_category.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/product_images_repository.dart';
import '../admin_dashboard/admin_shell.dart';
import 'admin_product_discount_helpers.dart';
import 'admin_product_operational_card.dart';
import 'admin_product_quick_sheets.dart';
import 'category_editor_dialog.dart';

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
  List<ProductCategory> categoryModels = const [];
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
  bool _savingProduct = false;
  _AdminQuickFilter quickFilter = _AdminQuickFilter.all;
  bool multiSelectMode = false;
  final Set<String> selectedProductIds = {};
  final Set<String> busyProductIds = {};

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
    listenForScreenReload(
      ref,
      () => _reloadProducts(refreshMetadata: true),
    );
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
              ? const ShopLoading.compact()
              : const Icon(Icons.refresh),
          tooltip: 'تحديث المنتجات والتصنيفات',
        ),
        IconButton(
            onPressed: () => _showProductForm(),
            icon: const Icon(Icons.add_box),
            tooltip: 'منتج جديد')
      ],
      child: ShopRefreshIndicator(
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
            ProductChipWrap(
              key: const ValueKey('admin-products-quick-filters'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _AdminQuickFilter.values)
                  ChoiceChip(
                    key: ValueKey('admin-quick-filter-${option.name}'),
                    label: Text(option.label),
                    selected: quickFilter == option,
                    onSelected: (_) => _selectQuickFilter(option),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('admin-products-multi-select-toggle'),
                  onPressed: _toggleMultiSelectMode,
                  icon: Icon(
                    multiSelectMode
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                  ),
                  label: Text(
                    multiSelectMode ? 'إلغاء التحديد' : 'تحديد متعدد',
                  ),
                ),
                if (multiSelectMode && selectedProductIds.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${selectedProductIds.length} محدد',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
            if (multiSelectMode && selectedProductIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              _AdminBulkActionBar(
                onDiscount: () => unawaited(_bulkApplyDiscount()),
                onPrices: () => unawaited(_bulkAdjustPrices()),
                onFeatured: () => unawaited(_bulkSetFeatured(true)),
                onVisibility: (visible) =>
                    unawaited(_bulkSetVisibility(visible)),
                onCategory: () => unawaited(_bulkChangeCategory()),
                onClear: _clearSelection,
              ),
            ],
            const SizedBox(height: 10),
            ProductChipWrap(
              key: const ValueKey('admin-products-category-chips'),
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('admin-products-category-all'),
                  label: const Text('الكل'),
                  selected: category == null,
                  onSelected: (_) => _selectCategory(null),
                ),
                for (final value in categories)
                  ChoiceChip(
                    key: ValueKey('admin-products-category-$value'),
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
              const ShopSkeleton(
                semanticLabel: 'جارٍ تحميل المنتجات...',
                child: ShopProductListSkeleton(
                  itemCount: 4,
                  padding: EdgeInsets.zero,
                ),
              )
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
                      ? const ShopLoading.compact()
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
        quickFilter == _AdminQuickFilter.all ? null : quickFilter,
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
      if (quickFilter != _AdminQuickFilter.all)
        _AdminProductFilterChipData(
          label: quickFilter.label,
          onDeleted: () => _removeProductFilter(
            () => quickFilter = _AdminQuickFilter.all,
          ),
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
      quickFilter = _AdminQuickFilter.all;
    });
    unawaited(_reloadProducts());
  }

  void _selectQuickFilter(_AdminQuickFilter value) {
    if (quickFilter == value) return;
    setState(() {
      quickFilter = value;
      availability = switch (value) {
        _AdminQuickFilter.lowStock => 'low_stock',
        _AdminQuickFilter.outOfStock => 'out_of_stock',
        _ => 'all',
      };
    });
    unawaited(_reloadProducts());
  }

  void _toggleMultiSelectMode() {
    setState(() {
      multiSelectMode = !multiSelectMode;
      if (!multiSelectMode) selectedProductIds.clear();
    });
  }

  void _clearSelection() {
    setState(() => selectedProductIds.clear());
  }

  void _toggleProductSelected(String id) {
    setState(() {
      if (selectedProductIds.contains(id)) {
        selectedProductIds.remove(id);
      } else {
        selectedProductIds.add(id);
      }
    });
  }

  List<Product> _applyQuickFilter(List<Product> source) {
    return switch (quickFilter) {
      _AdminQuickFilter.offers =>
        source.where((product) => product.hasProductDiscount).toList(),
      _AdminQuickFilter.featured =>
        source.where((product) => product.isFeatured).toList(),
      _AdminQuickFilter.hidden => source
          .where((product) => !product.active && !product.isArchived)
          .toList(),
      _ => source,
    };
  }

  Product? _productById(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  void _replaceProductLocally(Product next) {
    setState(() {
      products = [
        for (final product in products)
          if (product.id == next.id) next else product,
      ];
    });
  }

  Future<void> _persistProductPatch(
    Product before,
    Product after, {
    bool showUndo = false,
    String? undoMessage,
    Future<void> Function()? onUndo,
  }) async {
    if (busyProductIds.contains(before.id)) return;
    setState(() => busyProductIds.add(before.id));
    _replaceProductLocally(after);
    try {
      final saved =
          await ref.read(catalogRepositoryProvider).saveProduct(after);
      _replaceProductLocally(saved);
      if (!mounted) return;
      if (showUndo && undoMessage != null && onUndo != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(undoMessage),
            action: SnackBarAction(
              label: 'تراجع',
              onPressed: () => unawaited(onUndo()),
            ),
          ),
        );
      }
    } on StaleWriteException catch (error) {
      _replaceProductLocally(before);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      await reloadAfterMutation(
        this,
        () => _reloadProducts(refreshMetadata: true),
      );
    } catch (error) {
      _replaceProductLocally(before);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mutationFailureMessageAr(
              error,
              fallback: 'تعذر حفظ التغيير. تم التراجع عن التعديل.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busyProductIds.remove(before.id));
    }
  }

  Future<void> _quickEditPrice(Product product) async {
    final nextPrice = await showAdminQuickPriceSheet(
      context: context,
      product: product,
    );
    if (nextPrice == null || !mounted) return;
    final after = product.copyWith(basePrice: nextPrice);
    await _persistProductPatch(product, after);
  }

  Future<void> _quickEditDiscount(Product product) async {
    final percent = await showAdminQuickDiscountSheet(
      context: context,
      product: product,
    );
    if (percent == null || !mounted) return;
    final after = percent <= 0
        ? clearProductDiscount(product)
        : applyProductDiscount(product, percent);
    await _persistProductPatch(
      product,
      after,
      showUndo: true,
      undoMessage: 'تم حفظ التغيير',
      onUndo: () async {
        await _persistProductPatch(after, product, showUndo: false);
      },
    );
  }

  Future<void> _quickEditStock(Product product) async {
    final nextStock = await showAdminQuickStockSheet(
      context: context,
      product: product,
    );
    if (nextStock == null || !mounted) return;
    final after = product.copyWith(
      stockQuantity: nextStock,
      availableQuantity: product.stockTrackingEnabled
          ? nextStock - product.reservedQuantity
          : product.availableQuantity,
    );
    await _persistProductPatch(product, after);
  }

  Future<void> _toggleFeatured(Product product, {bool showUndo = true}) async {
    final after = product.copyWith(isFeatured: !product.isFeatured);
    await _persistProductPatch(
      product,
      after,
      showUndo: showUndo,
      undoMessage: 'تم حفظ التغيير',
      onUndo: () async {
        await _toggleFeatured(after, showUndo: false);
      },
    );
  }

  Future<void> _toggleVisibility(Product product,
      {bool showUndo = true}) async {
    if (product.isArchived) return;
    final after = product.copyWith(isActive: !product.active);
    await _persistProductPatch(
      product,
      after,
      showUndo: showUndo,
      undoMessage: 'تم حفظ التغيير',
      onUndo: () async {
        await _toggleVisibility(after, showUndo: false);
      },
    );
  }

  Future<void> _handleQuickAction(Product product, String action) async {
    switch (action) {
      case 'price':
        await _quickEditPrice(product);
      case 'discount':
        await _quickEditDiscount(product);
      case 'stock':
        await _quickEditStock(product);
    }
  }

  Future<void> _bulkApplyDiscount() async {
    final ids = selectedProductIds.toList(growable: false);
    if (ids.isEmpty) return;
    final percent = await showAdminBulkDiscountSheet(
      context: context,
      productCount: ids.length,
    );
    if (percent == null || !mounted) return;
    for (final id in ids) {
      final product = _productById(id);
      if (product == null) continue;
      final after = applyProductDiscount(product, percent);
      await _persistProductPatch(product, after, showUndo: false);
    }
  }

  Future<void> _bulkAdjustPrices() async {
    final ids = selectedProductIds.toList(growable: false);
    if (ids.isEmpty) return;
    final selection = await showAdminBulkPriceSheet(
      context: context,
      productCount: ids.length,
    );
    if (selection == null || !mounted) return;
    for (final id in ids) {
      final product = _productById(id);
      if (product == null) continue;
      final next = bulkAdjustedPrice(
        product.basePrice,
        percentDelta: selection.percent,
      );
      if (next <= 0) continue;
      final after = product.copyWith(basePrice: next);
      await _persistProductPatch(product, after, showUndo: false);
    }
  }

  Future<void> _bulkSetFeatured(bool featured) async {
    for (final id in selectedProductIds.toList()) {
      final product = _productById(id);
      if (product == null || product.isFeatured == featured) continue;
      await _persistProductPatch(
        product,
        product.copyWith(isFeatured: featured),
        showUndo: false,
      );
    }
  }

  Future<void> _bulkSetVisibility(bool visible) async {
    for (final id in selectedProductIds.toList()) {
      final product = _productById(id);
      if (product == null || product.isArchived || product.active == visible) {
        continue;
      }
      await _persistProductPatch(
        product,
        product.copyWith(isActive: visible),
        showUndo: false,
      );
    }
  }

  Future<void> _bulkChangeCategory() async {
    if (categories.isEmpty) return;
    final selectedCategory = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('تغيير التصنيف'),
        children: [
          for (final value in categories)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Text(value),
            ),
        ],
      ),
    );
    if (selectedCategory == null || !mounted) return;
    for (final id in selectedProductIds.toList()) {
      final product = _productById(id);
      if (product == null || product.category == selectedCategory) continue;
      await _persistProductPatch(
        product,
        product.copyWith(category: selectedCategory, categoryId: null),
        showUndo: false,
      );
    }
  }

  Future<void> _duplicateProduct(Product product) async {
    final draftUuid = const Uuid().v4();
    final copy = product.copyWith(
      id: 'local-$draftUuid',
      nameAr: '${product.nameAr} (نسخة)',
      sku:
          'COPY-${draftUuid.replaceAll('-', '').substring(0, 8).toUpperCase()}',
      isFeatured: false,
      archivedAt: null,
      createdAt: null,
      updatedAt: null,
    );
    await _showProductForm(copy);
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
    return Column(
      key: const ValueKey('admin-products-results'),
      children: [
        for (final product in products)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AdminProductOperationalCard(
              product: product,
              busy: busyProductIds.contains(product.id),
              multiSelectMode: multiSelectMode,
              selected: selectedProductIds.contains(product.id),
              onToggleSelected: () => _toggleProductSelected(product.id),
              onQuickAction: (action) =>
                  unawaited(_handleQuickAction(product, action)),
              onMenuAction: (value) => _handleProductAction(product, value),
              onFeaturedToggle: () => unawaited(_toggleFeatured(product)),
              onVisibilityToggle: () => unawaited(_toggleVisibility(product)),
              onOpenFullEdit: () => unawaited(_showProductForm(product)),
              compact: viewMode == _AdminProductViewMode.compact,
            ),
          ),
      ],
    );
  }

  Future<void> _handleProductAction(Product product, String value) async {
    if (value == 'edit') {
      await _showProductForm(product);
    } else if (value == 'change-image') {
      await _showProductForm(product);
    } else if (value == 'duplicate') {
      await _duplicateProduct(product);
    } else if (value == 'stock-settings') {
      await _showProductForm(product);
    } else if (value == 'toggle-featured') {
      await _toggleFeatured(product);
    } else if (value == 'toggle-visibility') {
      await _toggleVisibility(product);
    } else if (value == 'copy-name') {
      await _copyProductText(product.name, 'تم نسخ اسم المنتج');
    } else if (value == 'copy-sku') {
      await _copyProductText(product.sku, 'تم نسخ رقم الصنف');
    } else if (value == 'archive') {
      await _archiveProduct(product);
    } else if (value == 'restore') {
      await _restoreProduct(product);
    }
  }

  Future<void> _copyProductText(String value, String message) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !mounted) return;
    await Clipboard.setData(ClipboardData(text: trimmed));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
      final optionsFuture =
          shouldLoadMetadata ? _loadAdminFilterOptionsSafely() : null;
      final categoryModelsFuture =
          shouldLoadMetadata ? _loadProductCategoriesSafely() : null;
      final options = optionsFuture == null ? null : await optionsFuture;
      final loadedCategoryModels =
          categoryModelsFuture == null ? null : await categoryModelsFuture;
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
        products = _applyQuickFilter(
          page.products
              .where(
                (product) =>
                    !product.isArchived || product.archivedByCategoryId == null,
              )
              .toList(growable: false),
        );
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
        if (loadedCategoryModels != null) {
          categoryModels = loadedCategoryModels;
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

  Future<List<ProductCategory>?> _loadProductCategoriesSafely() async {
    try {
      return await ref.read(catalogRepositoryProvider).productCategories();
    } catch (_) {
      return null;
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

  ProductCategory _categoryModelByName(String name) {
    for (final item in categoryModels) {
      if (item.name == name) return item;
    }
    return ProductCategory(id: name, name: name);
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
        products = _applyQuickFilter(_deduplicateAdminProducts([
          ...products,
          ...page.products.where(
            (product) =>
                !product.isArchived || product.archivedByCategoryId == null,
          ),
        ]));
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
    await reloadAfterMutation(
      this,
      () => _reloadProducts(refreshMetadata: true),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إنشاء تصنيف «${created.name}».')),
    );
  }

  Future<ProductCategory?> _promptAndCreateCategory() async {
    final result = await showCategoryEditorDialog(context: context);
    if (result == null || !mounted) return null;
    try {
      return await ref.read(catalogRepositoryProvider).createCategory(
            result.name,
            iconKey: result.iconKey,
            iconUrl: result.iconUrl,
          );
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
    } on CategoryIconRequiredException {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر أيقونة جاهزة أو ارفع أيقونة للتصنيف.'),
        ),
      );
      return null;
    } on CategoryIconInvalidException {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'استخدم رابط https صالحاً للأيقونة، أو اختر أيقونة جاهزة.',
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

  Future<ProductCategory?> _promptAndUpdateCategory(
    ProductCategory existing,
  ) async {
    final result = await showCategoryEditorDialog(
      context: context,
      existing: existing,
    );
    if (result == null || !mounted) return null;
    try {
      return await ref.read(catalogRepositoryProvider).updateCategory(
            existing.id,
            name: result.name,
            iconKey: result.iconKey,
            iconUrl: result.iconUrl,
            expectedUpdatedAt: existing.updatedAt,
          );
    } on CategoryArchivedException {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'هذا التصنيف مؤرشف. استعده من قسم «الأرشيف» قبل التعديل.',
          ),
        ),
      );
      return null;
    } on CategoryIconRequiredException {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر أيقونة جاهزة أو ارفع أيقونة للتصنيف.'),
        ),
      );
      return null;
    } on CategoryIconInvalidException {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'استخدم رابط https صالحاً للأيقونة، أو اختر أيقونة جاهزة.',
          ),
        ),
      );
      return null;
    } on StaleWriteException catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return null;
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر حفظ التصنيف. تحقق من الاسم والأيقونة والاتصال وحاول مجدداً.',
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
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: .12),
                          child: CategoryIconView.fromCategory(
                            item,
                            size: 22,
                          ),
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
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey(
                                      'edit-category-${item.id}',
                                    ),
                                    tooltip: 'تعديل التصنيف وأيقونته',
                                    onPressed: () async {
                                      final updated =
                                          await _promptAndUpdateCategory(item);
                                      if (updated == null ||
                                          !mounted ||
                                          !dialogContext.mounted) {
                                        return;
                                      }
                                      try {
                                        managedCategories = await repository
                                            .productCategories();
                                      } catch (_) {
                                        managedCategories = [
                                          for (final category
                                              in managedCategories)
                                            if (category.id == updated.id)
                                              updated
                                            else
                                              category,
                                        ];
                                      }
                                      if (!dialogContext.mounted) return;
                                      setDialogState(() {});
                                      await reloadAfterMutation(
                                        this,
                                        () => _reloadProducts(
                                          refreshMetadata: true,
                                        ),
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'تم حفظ تصنيف «${updated.name}».',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
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
                                        await repository
                                            .archiveCategory(item.id);
                                      } catch (_) {
                                        if (!mounted ||
                                            !dialogContext.mounted) {
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
                                        managedCategories = await repository
                                            .productCategories();
                                      } catch (_) {
                                        categoryRefreshFailed = true;
                                        managedCategories = managedCategories
                                            .where(
                                              (category) =>
                                                  category.id != item.id,
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
                                      await reloadAfterMutation(
                                        this,
                                        () => _reloadProducts(
                                          refreshMetadata: true,
                                        ),
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
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                ],
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
                      await reloadAfterMutation(
                        this,
                        () => _reloadProducts(refreshMetadata: true),
                      );
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
    final discountPct = TextEditingController(
        text: (product?.discountPercent ?? 0) > 0
            ? (product!.discountPercent!).toStringAsFixed(0)
            : '');
    final bulkMinimum =
        TextEditingController(text: product?.minOrderQty.toString() ?? '1');
    final stock = TextEditingController(
      text: product?.stockQuantity.toString() ?? '',
    );
    final unitsPerBox =
        TextEditingController(text: product?.unitsPerBox?.toString() ?? '');
    final imageUrl = TextEditingController(text: product?.imageUrl ?? '');
    final scrollController = ScrollController();
    var uploadingImage = false;
    double? imageUploadProgress;
    String? imageUploadError;
    Uint8List? imagePreviewBytes;
    var stockTrackingEnabled = product?.stockTrackingEnabled ?? false;
    var showStockQuantityToCustomers =
        product?.showStockQuantityToCustomers ?? false;
    var active =
        product?.isArchived == true ? false : product?.isActive ?? true;
    var featured = product?.isFeatured ?? false;
    var hideWhenOutOfStock = product?.hideWhenOutOfStock ?? false;
    var fieldErrors = <_ProductFormField, String>{};
    final reservedQuantity = product?.reservedQuantity ?? 0;
    final nameFocus = FocusNode();
    final companyFocus = FocusNode();
    final priceFocus = FocusNode();
    final retailPriceFocus = FocusNode();
    final discountPctFocus = FocusNode();
    final bulkMinimumFocus = FocusNode();
    final unitsPerBoxFocus = FocusNode();
    final stockFocus = FocusNode();
    final imageUrlFocus = FocusNode();
    FocusNode? categoryFocus;
    final imageKey = GlobalKey();
    final nameKey = GlobalKey();
    final categoryKey = GlobalKey();
    final companyKey = GlobalKey();
    final priceKey = GlobalKey();
    final retailPriceKey = GlobalKey();
    final discountPctKey = GlobalKey();
    final bulkMinimumKey = GlobalKey();
    final unitsPerBoxKey = GlobalKey();
    final stockKey = GlobalKey();
    final trackingKey = GlobalKey();

    void revealFirstInvalidField(Map<_ProductFormField, String> errors) {
      final first = _ProductFormField.values.firstWhere(errors.containsKey);
      final anchors = <_ProductFormField, GlobalKey>{
        _ProductFormField.image: imageKey,
        _ProductFormField.name: nameKey,
        _ProductFormField.category: categoryKey,
        _ProductFormField.company: companyKey,
        _ProductFormField.price: priceKey,
        _ProductFormField.retailPrice: retailPriceKey,
        _ProductFormField.discountPercent: discountPctKey,
        _ProductFormField.bulkMinimum: bulkMinimumKey,
        _ProductFormField.unitsPerBox: unitsPerBoxKey,
        _ProductFormField.stock: stockKey,
        _ProductFormField.tracking: trackingKey,
      };
      final focuses = <_ProductFormField, FocusNode?>{
        _ProductFormField.image: imageUrlFocus,
        _ProductFormField.name: nameFocus,
        _ProductFormField.category: categoryFocus,
        _ProductFormField.company: companyFocus,
        _ProductFormField.price: priceFocus,
        _ProductFormField.retailPrice: retailPriceFocus,
        _ProductFormField.discountPercent: discountPctFocus,
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
        builder: (context, setDialogState) {
          final images = ref.read(productImagesRepositoryProvider);
          Future<void> uploadProductImage() async {
            setDialogState(() {
              imageUploadError = null;
              fieldErrors.remove(_ProductFormField.image);
            });
            try {
              final picked = await images.pick();
              if (!context.mounted) return;
              if (picked == null) return;
              setDialogState(() {
                imagePreviewBytes = picked.bytes;
                uploadingImage = true;
                imageUploadProgress = 0;
              });
              final result = await images.uploadPicked(
                picked,
                onProgress: (fraction) {
                  if (!context.mounted) return;
                  setDialogState(() => imageUploadProgress = fraction);
                },
              );
              if (!context.mounted) return;
              imageUrl.text = result.publicUrl;
              setDialogState(() {
                uploadingImage = false;
                imageUploadProgress = 1;
              });
            } on ProductImageUploadException catch (error) {
              if (!context.mounted) return;
              setDialogState(() {
                uploadingImage = false;
                imageUploadProgress = null;
                imageUploadError = error.message;
              });
            } catch (error) {
              if (!context.mounted) return;
              setDialogState(() {
                uploadingImage = false;
                imageUploadProgress = null;
                imageUploadError = mapProductImageUploadError(
                  error,
                  folder: ProductImagesRepository.productsFolder,
                ).message;
              });
            }
          }

          return AlertDialog(
            title: Text(editing ? 'تعديل المنتج' : 'منتج جديد'),
            content: SizedBox(
              width: 620,
              child: ScrollbarTheme(
                data: ScrollbarThemeData(
                  thumbColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.primary,
                  ),
                  trackColor: WidgetStateProperty.all(
                    Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.10),
                  ),
                  trackBorderColor: WidgetStateProperty.all(
                    Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.18),
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
                            key: imageKey,
                            child: _ProductImageEditor(
                              category: selectedCategory,
                              productId: product?.id,
                              imageUrl: imageUrl.text,
                              imageBytes: imagePreviewBytes,
                              urlController: imageUrl,
                              urlFocus: imageUrlFocus,
                              uploading: uploadingImage,
                              uploadProgress: imageUploadProgress,
                              canUpload: images.canUpload,
                              demoMode: AppConfig.isDemoMode,
                              errorText: fieldErrors[_ProductFormField.image] ??
                                  imageUploadError,
                              onUpload: uploadProductImage,
                              onUrlChanged: () => setDialogState(() {
                                imagePreviewBytes = null;
                                fieldErrors.remove(_ProductFormField.image);
                                imageUploadError = null;
                              }),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            key: const ValueKey('product-form-scroll-hint'),
                            children: [
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              const Expanded(
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
                          const SizedBox(height: 10),
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
                                (option) =>
                                    option.toLowerCase().contains(query),
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
                                errorText:
                                    fieldErrors[_ProductFormField.company],
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
                          KeyedSubtree(
                            key: discountPctKey,
                            child: TextField(
                              key: const ValueKey('product-discount-pct-field'),
                              controller: discountPct,
                              focusNode: discountPctFocus,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onChanged: (_) => setDialogState(() {
                                fieldErrors.remove(
                                  _ProductFormField.discountPercent,
                                );
                              }),
                              decoration: InputDecoration(
                                labelText: 'خصم المنتج (%)',
                                helperText: 'أدخل 0 إذا لم يكن هناك خصم. '
                                    'السعر المعروض للعميل = سعر الجملة × (1 − الخصم/100).',
                                helperMaxLines: 2,
                                errorText: fieldErrors[
                                    _ProductFormField.discountPercent],
                              ),
                            ),
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
                                style:
                                    fieldErrors[_ProductFormField.tracking] ==
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
                          const SizedBox(height: 4),
                          SwitchListTile.adaptive(
                            key: const ValueKey('product-featured-switch'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('منتج مميز'),
                            subtitle: const Text(
                              'يظهر ضمن قسم المنتجات المميزة في الصفحة الرئيسية للعملاء.',
                            ),
                            value: featured,
                            onChanged: (value) => setDialogState(() {
                              featured = value;
                            }),
                          ),
                          if (stockTrackingEnabled) ...[
                            const SizedBox(height: 4),
                            SwitchListTile.adaptive(
                              key: const ValueKey(
                                'product-hide-when-out-of-stock-switch',
                              ),
                              contentPadding: EdgeInsets.zero,
                              title:
                                  const Text('إخفاء المنتج عند نفاد المخزون'),
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
                onPressed: uploadingImage
                    ? null
                    : () {
                        final parsedPrice = _parseLocalizedDouble(price.text);
                        final parsedRetailPrice =
                            _parseLocalizedDouble(retailPrice.text);
                        final parsedDiscountPct =
                            discountPct.text.trim().isEmpty
                                ? 0.0
                                : _parseLocalizedDouble(discountPct.text);
                        final parsedBulkMinimum =
                            _parseLocalizedInt(bulkMinimum.text);
                        final parsedStock = _parseLocalizedInt(stock.text);
                        final parsedUnitsPerBox =
                            unitsPerBox.text.trim().isEmpty
                                ? null
                                : _parseLocalizedInt(unitsPerBox.text);
                        final trimmedImageUrl = imageUrl.text.trim();
                        final errors = <_ProductFormField, String>{};
                        if (trimmedImageUrl.isNotEmpty &&
                            safeHttpsUpdateUri(trimmedImageUrl) == null) {
                          errors[_ProductFormField.image] =
                              'استخدم رابط https صالحاً ومن دون بيانات دخول، أو ارفع صورة.';
                        }
                        if (name.text.trim().isEmpty) {
                          errors[_ProductFormField.name] = 'أدخل اسم المنتج.';
                        }
                        if (selectedCategory.trim().isEmpty) {
                          errors[_ProductFormField.category] =
                              'اختر تصنيفاً أو اكتب اسم تصنيف جديد.';
                        }
                        if (company.text.trim().isEmpty) {
                          errors[_ProductFormField.company] =
                              'أدخل اسم الشركة.';
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
                        if (parsedDiscountPct == null ||
                            !parsedDiscountPct.isFinite ||
                            parsedDiscountPct < 0 ||
                            parsedDiscountPct > 100) {
                          errors[_ProductFormField.discountPercent] =
                              'أدخل نسبة خصم بين 0 و 100، أو اتركها فارغة لعدم وجود خصم.';
                        }
                        if (parsedBulkMinimum == null ||
                            parsedBulkMinimum < 1 ||
                            parsedBulkMinimum > 1000000) {
                          errors[_ProductFormField.bulkMinimum] =
                              'الحد الأدنى لطلب الجملة يجب أن يكون رقماً صحيحاً موجباً.';
                        }
                        if (parsedUnitsPerBox != null &&
                            (parsedUnitsPerBox < 1 ||
                                parsedUnitsPerBox > 1000000)) {
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
                        final internalSku = product?.sku.trim().isNotEmpty ==
                                true
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
                            discountPercent: parsedDiscountPct == 0
                                ? null
                                : parsedDiscountPct,
                            stockQuantity: resolvedStock,
                            availableQuantity:
                                stockTrackingEnabled && product != null
                                    ? resolvedStock - reservedQuantity
                                    : null,
                            stockTrackingEnabled: stockTrackingEnabled,
                            showStockQuantityToCustomers:
                                stockTrackingEnabled &&
                                    showStockQuantityToCustomers,
                            hideWhenOutOfStock: hideWhenOutOfStock,
                            unitsPerBox: parsedUnitsPerBox,
                            minOrderQty: parsedBulkMinimum!,
                            descriptionAr: product?.descriptionAr ?? '',
                            imageUrl: trimmedImageUrl.isEmpty
                                ? null
                                : safeHttpsUpdateUri(trimmedImageUrl)
                                    ?.toString(),
                            imageAttribution: product?.imageAttribution,
                            sourceUrl: product?.sourceUrl,
                            isActive: active,
                            isFeatured: featured,
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
          );
        },
      ),
    );
    final saved = await navigator.push(dialogRoute);
    await dialogRoute.completed;

    for (final controller in [
      name,
      company,
      price,
      retailPrice,
      discountPct,
      bulkMinimum,
      stock,
      unitsPerBox,
      imageUrl,
    ]) {
      controller.dispose();
    }
    for (final focus in [
      nameFocus,
      companyFocus,
      priceFocus,
      retailPriceFocus,
      discountPctFocus,
      bulkMinimumFocus,
      unitsPerBoxFocus,
      stockFocus,
      imageUrlFocus,
    ]) {
      focus.dispose();
    }
    scrollController.dispose();
    if (saved == null) return;
    if (_savingProduct) return;
    setState(() => _savingProduct = true);
    try {
      await ref.read(catalogRepositoryProvider).saveProduct(saved);
      if (mounted) {
        await reloadAfterMutation(
          this,
          () => _reloadProducts(refreshMetadata: true),
        );
      }
    } on StaleWriteException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      await reloadAfterMutation(
        this,
        () => _reloadProducts(refreshMetadata: true),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mutationFailureMessageAr(
              error,
              fallback:
                  'تعذر حفظ المنتج. تحقق من البيانات والاتصال وحاول مجدداً.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingProduct = false);
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
      await reloadAfterMutation(
        this,
        () => _reloadProducts(refreshMetadata: true),
      );
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
      await reloadAfterMutation(
        this,
        () => _reloadProducts(refreshMetadata: true),
      );
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
  image,
  name,
  category,
  company,
  price,
  retailPrice,
  discountPercent,
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

enum _AdminQuickFilter {
  all('الكل'),
  offers('🔥 العروض'),
  featured('⭐ المميزة'),
  lowStock('⚠️ مخزون منخفض'),
  outOfStock('نفد المخزون'),
  hidden('مخفي');

  const _AdminQuickFilter(this.label);

  final String label;
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

class _AdminBulkActionBar extends StatelessWidget {
  const _AdminBulkActionBar({
    required this.onDiscount,
    required this.onPrices,
    required this.onFeatured,
    required this.onVisibility,
    required this.onCategory,
    required this.onClear,
  });

  final VoidCallback onDiscount;
  final VoidCallback onPrices;
  final VoidCallback onFeatured;
  final ValueChanged<bool> onVisibility;
  final VoidCallback onCategory;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('admin-products-bulk-toolbar'),
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .06),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              key: const ValueKey('admin-bulk-discount'),
              onPressed: onDiscount,
              child: const Text('الخصم'),
            ),
            FilledButton.tonal(
              key: const ValueKey('admin-bulk-prices'),
              onPressed: onPrices,
              child: const Text('الأسعار'),
            ),
            FilledButton.tonal(
              key: const ValueKey('admin-bulk-featured'),
              onPressed: onFeatured,
              child: const Text('تمييز'),
            ),
            FilledButton.tonal(
              key: const ValueKey('admin-bulk-show'),
              onPressed: () => onVisibility(true),
              child: const Text('إظهار'),
            ),
            FilledButton.tonal(
              key: const ValueKey('admin-bulk-hide'),
              onPressed: () => onVisibility(false),
              child: const Text('إخفاء'),
            ),
            FilledButton.tonal(
              key: const ValueKey('admin-bulk-category'),
              onPressed: onCategory,
              child: const Text('التصنيف'),
            ),
            OutlinedButton(
              key: const ValueKey('admin-bulk-clear'),
              onPressed: onClear,
              child: const Text('إلغاء التحديد'),
            ),
          ],
        ),
      ),
    );
  }
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

class _ProductImageEditor extends StatelessWidget {
  const _ProductImageEditor({
    required this.category,
    required this.productId,
    required this.imageUrl,
    this.imageBytes,
    required this.urlController,
    required this.urlFocus,
    required this.uploading,
    this.uploadProgress,
    required this.canUpload,
    required this.demoMode,
    required this.errorText,
    required this.onUpload,
    required this.onUrlChanged,
  });

  final String category;
  final String? productId;
  final String imageUrl;
  final Uint8List? imageBytes;
  final TextEditingController urlController;
  final FocusNode urlFocus;
  final bool uploading;
  final double? uploadProgress;
  final bool canUpload;
  final bool demoMode;
  final String? errorText;
  final VoidCallback onUpload;
  final VoidCallback onUrlChanged;

  @override
  Widget build(BuildContext context) {
    final previewUrl = safeHttpsUpdateUri(imageUrl)?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'صورة المنتج',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ProductImagePlaceholder(
                    key: const ValueKey('product-image-preview'),
                    category: category.trim().isEmpty ? 'عام' : category,
                    productId: productId,
                    imageUrl: previewUrl,
                    imageBytes: imageBytes,
                    semanticLabel: 'معاينة صورة المنتج',
                    size: 72,
                  ),
                  if (uploading)
                    _ProductImageUploadProgress(progress: uploadProgress),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('product-image-upload-button'),
                    onPressed: uploading || !canUpload ? null : onUpload,
                    icon: uploading
                        ? const SizedBox.shrink()
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      uploading
                          ? _productImageUploadLabel(uploadProgress)
                          : 'رفع صورة',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    demoMode || !canUpload
                        ? 'الرفع من الجهاز يحتاج ربط الإنتاج. يمكنك لصق رابط https الآن.'
                        : 'JPEG أو PNG أو WebP حتى 5 ميغابايت.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade700,
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('product-image-url-field'),
          controller: urlController,
          focusNode: urlFocus,
          enabled: !uploading,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
          onChanged: (_) => onUrlChanged(),
          decoration: InputDecoration(
            labelText: 'أو رابط https',
            hintText: 'https://',
            helperText: 'اختياري. يُعرض للعملاء بعد الحفظ.',
            errorText: errorText,
            errorMaxLines: 4,
          ),
        ),
      ],
    );
  }
}

class _ProductImageUploadProgress extends StatelessWidget {
  const _ProductImageUploadProgress({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final percent =
        progress == null ? null : (progress!.clamp(0, 1) * 100).round();
    return SizedBox(
      key: const ValueKey('product-image-upload-progress'),
      width: 72,
      height: 72,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              percent == null ? '...' : '$percent٪',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _productImageUploadLabel(double? progress) {
  if (progress == null) return 'جارٍ الرفع...';
  return 'جارٍ الرفع ${((progress.clamp(0, 1)) * 100).round()}٪';
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
