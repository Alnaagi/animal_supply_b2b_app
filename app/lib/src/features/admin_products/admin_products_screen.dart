import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
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
  List<Product> products = const [];
  List<String> categories = const [];
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
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 72)
                      .clamp(220.0, 360.0),
                  child: TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'بحث باسم المنتج أو الشركة',
                    ),
                    onSubmitted: (_) => unawaited(_reloadProducts()),
                  ),
                ),
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: category == null,
                  onSelected: (_) => _selectCategory(null),
                ),
                for (final value in categories.take(8))
                  ChoiceChip(
                    label: Text(value),
                    selected: category == value,
                    onSelected: (_) => _selectCategory(value),
                  ),
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
              const Card(
                child: ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('لا توجد منتجات بهذا البحث'),
                ),
              )
            else ...[
              for (final product in products)
                Card(
                  key: ValueKey('admin-product-card-${product.id}'),
                  child: _AdminProductCard(
                    product: product,
                    onSelected: (value) async {
                      if (value == 'edit') {
                        _showProductForm(product);
                      } else if (value == 'archive') {
                        await _archiveProduct(product);
                      } else if (value == 'restore') {
                        await _restoreProduct(product);
                      }
                    },
                  ),
                ),
              if (hasMore)
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
                          : 'تحميل المزيد',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _selectCategory(String? value) {
    if (category == value) return;
    setState(() => category = value);
    unawaited(_reloadProducts());
  }

  Future<CatalogPage> _loadProductsPage({
    required String? categoryFilter,
    DateTime? pageSnapshot,
    int offset = 0,
  }) {
    return ref.read(catalogRepositoryProvider).productsPage(
          query: search.text,
          category: categoryFilter,
          includeInactive: true,
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
      if (refreshMetadata &&
          options != null &&
          resolvedCategory != null &&
          !options.categories.contains(resolvedCategory)) {
        resolvedCategory = null;
      }
      final page = await _loadProductsPage(
        categoryFilter: resolvedCategory,
      );
      if (!mounted || revision != loadRevision) return;
      setState(() {
        category = resolvedCategory;
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
    String? validationMessage;
    final reservedQuantity = product?.reservedQuantity ?? 0;

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
                        TextField(
                          key: const ValueKey('product-name-field'),
                          controller: name,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'اسم المنتج',
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
                            validationMessage = null;
                          },
                          fieldViewBuilder: (
                            context,
                            controller,
                            focusNode,
                            onFieldSubmitted,
                          ) {
                            return TextField(
                              key: const ValueKey('product-category-field'),
                              controller: controller,
                              focusNode: focusNode,
                              textInputAction: TextInputAction.next,
                              onChanged: (value) {
                                selectedCategory = value;
                              },
                              onSubmitted: (_) => onFieldSubmitted(),
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.category_outlined),
                                labelText: 'التصنيف',
                                helperText:
                                    'اختر تصنيفاً موجوداً أو اكتب اسماً جديداً؛ '
                                    'سيُنشأ عند الحفظ.',
                                helperMaxLines: 2,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('product-company-field'),
                          controller: company,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'اسم الشركة',
                          ),
                        ),
                        const SizedBox(height: 12),
                        ResponsiveFieldGroup(
                          children: [
                            TextField(
                              key: const ValueKey('product-price-field'),
                              controller: price,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'سعر الجملة (د.ل)',
                                helperText: 'هذا هو السعر المستخدم في الطلب.',
                              ),
                            ),
                            TextField(
                              key: const ValueKey('product-retail-price-field'),
                              controller: retailPrice,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'سعر بيع الوحدة المقترح (د.ل)',
                                helperText:
                                    'مرجع للتاجر فقط ولا يدخل في الإجمالي.',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ResponsiveFieldGroup(
                          children: [
                            TextField(
                              key: const ValueKey('product-bulk-minimum-field'),
                              controller: bulkMinimum,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'الحد الأدنى لطلب الجملة',
                                helperText: 'لا يمكن للعميل طلب كمية أقل.',
                              ),
                            ),
                            TextField(
                              key:
                                  const ValueKey('product-units-per-box-field'),
                              controller: unitsPerBox,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'الكمية في الصندوق (اختياري)',
                                helperText:
                                    'مثال: 12. لن تظهر إذا تركتها فارغة.',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          key: const ValueKey('product-track-stock-switch'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('تقييد الطلب حسب المخزون'),
                          subtitle: const Text(
                            'عند إيقافه يبقى العدد مسجلاً داخلياً، '
                            'لكن يمكن الطلب دون حد مخزني.',
                          ),
                          value: stockTrackingEnabled,
                          onChanged: (value) => setDialogState(() {
                            stockTrackingEnabled = value;
                            if (!value) {
                              showStockQuantityToCustomers = false;
                            }
                            validationMessage = null;
                          }),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          key: const ValueKey('product-stock-field'),
                          controller: stock,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'كمية المخزون الداخلية (مطلوبة)',
                            helperText: reservedQuantity > 0
                                ? 'منها $reservedQuantity محجوزة لطلبات قائمة.'
                                : 'تُستخدم لإدارة المخزون حتى لو أخفيت العدد عن العملاء.',
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
                                    validationMessage = null;
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
                                    validationMessage = null;
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
                              validationMessage = null;
                            }),
                          ),
                        ],
                        if (validationMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            validationMessage!,
                            key: const ValueKey('product-form-validation'),
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
                String? error;
                if (name.text.trim().isEmpty) {
                  error = 'أدخل اسم المنتج.';
                } else if (selectedCategory.trim().isEmpty) {
                  error = 'اختر تصنيفاً أو اكتب اسم تصنيف جديد.';
                } else if (company.text.trim().isEmpty) {
                  error = 'أدخل اسم الشركة.';
                } else if (parsedPrice == null ||
                    !parsedPrice.isFinite ||
                    parsedPrice <= 0) {
                  error = 'أدخل سعر جملة صحيحاً أكبر من صفر.';
                } else if (parsedRetailPrice == null ||
                    !parsedRetailPrice.isFinite ||
                    parsedRetailPrice <= 0) {
                  error = 'أدخل سعر بيع وحدة مقترحاً صحيحاً أكبر من صفر.';
                } else if (parsedBulkMinimum == null ||
                    parsedBulkMinimum < 1 ||
                    parsedBulkMinimum > 1000000) {
                  error =
                      'الحد الأدنى لطلب الجملة يجب أن يكون رقماً صحيحاً موجباً.';
                } else if (parsedUnitsPerBox != null &&
                    (parsedUnitsPerBox < 1 || parsedUnitsPerBox > 1000000)) {
                  error = 'الكمية في الصندوق يجب أن تكون رقماً صحيحاً موجباً.';
                } else if (parsedStock == null || parsedStock < 0) {
                  error = 'أدخل كمية مخزون صحيحة لا تقل عن صفر.';
                } else if (stockTrackingEnabled &&
                    parsedStock < reservedQuantity) {
                  error =
                      'لا يمكن خفض المخزون عن الكمية المحجوزة ($reservedQuantity).';
                } else if (!stockTrackingEnabled && reservedQuantity > 0) {
                  error =
                      'لا يمكن إيقاف تتبع المخزون مع وجود $reservedQuantity قطعة محجوزة.';
                }
                if (error != null) {
                  setDialogState(() => validationMessage = error);
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

double? _parseLocalizedDouble(String value) =>
    double.tryParse(_normalizeLocalizedNumber(value));

int? _parseLocalizedInt(String value) {
  final normalized = _normalizeLocalizedNumber(value);
  if (normalized.contains('.')) return null;
  return int.tryParse(normalized);
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
              PopupMenuButton<String>(
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
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('تعديل'),
                  ),
                  if (product.isArchived)
                    const PopupMenuItem(
                      value: 'restore',
                      child: Text('استعادة ونشر المنتج'),
                    )
                  else
                    const PopupMenuItem(
                      value: 'archive',
                      child: Text('أرشفة المنتج'),
                    ),
                ],
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
