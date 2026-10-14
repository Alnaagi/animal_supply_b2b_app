import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/refresh/screen_reload.dart';
import '../../core/widgets/category_icon_view.dart';
import '../../core/widgets/shop_skeleton.dart';
import '../../core/widgets/shop_refresh_indicator.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/product.dart';
import '../../data/models/product_category.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../admin_dashboard/admin_shell.dart';

class AdminArchiveScreen extends ConsumerStatefulWidget {
  const AdminArchiveScreen({super.key});

  @override
  ConsumerState<AdminArchiveScreen> createState() => _AdminArchiveScreenState();
}

class _AdminArchiveScreenState extends ConsumerState<AdminArchiveScreen> {
  final _search = TextEditingController();
  final _busyItems = <String>{};

  _ArchiveData? _data;
  Object? _loadError;
  bool _loading = true;
  int _loadRevision = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final revision = ++_loadRevision;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final catalog = ref.read(catalogRepositoryProvider);
      final admin = ref.read(adminRepositoryProvider);
      final results = await Future.wait<Object>([
        catalog.archivedProducts(),
        catalog.productCategories(includeArchived: true),
        admin.listCustomers(status: 'archived'),
      ]);
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _data = _ArchiveData(
          products: (results[0] as List<Product>)
              .where((product) => product.isArchived)
              .toList(growable: false),
          categories: (results[1] as List<ProductCategory>)
              .where((category) => category.isArchived)
              .toList(growable: false),
          customers: (results[2] as List<BusinessCustomer>)
              .where((customer) => customer.accountStatus == 'archived')
              .toList(growable: false),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    listenForScreenReload(ref, _reload);
    final data = _data;
    final products = data?.matchingProducts(_query) ?? const <Product>[];
    final categories =
        data?.matchingCategories(_query) ?? const <ProductCategory>[];
    final customers =
        data?.matchingCustomers(_query) ?? const <BusinessCustomer>[];

    return AdminShell(
      title: 'الأرشيف',
      actions: [
        IconButton(
          onPressed: _loading ? null : _reload,
          tooltip: 'تحديث الأرشيف',
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: .18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'العناصر المؤرشفة محفوظة ولا تُحذف نهائياً. '
                            'يمكنك البحث عنها واستعادتها من هنا.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('admin-archive-search'),
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: 'بحث في الأرشيف',
                      suffixIcon: _query.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            TabBar(
              tabs: [
                Tab(
                  key: const ValueKey('admin-archive-products-tab'),
                  icon: const Icon(Icons.inventory_2_outlined),
                  text: _tabLabel('المنتجات', data?.products.length),
                ),
                Tab(
                  key: const ValueKey('admin-archive-categories-tab'),
                  icon: const Icon(Icons.category_outlined),
                  text: _tabLabel('التصنيفات', data?.categories.length),
                ),
                Tab(
                  key: const ValueKey('admin-archive-customers-tab'),
                  icon: const Icon(Icons.groups_outlined),
                  text: _tabLabel('العملاء', data?.customers.length),
                ),
              ],
            ),
            if (_loadError != null && _data != null)
              _ArchiveRefreshErrorNotice(
                onRetry: () => unawaited(_reload()),
              ),
            Expanded(
              child: _buildBody(
                products: products,
                categories: categories,
                customers: customers,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({
    required List<Product> products,
    required List<ProductCategory> categories,
    required List<BusinessCustomer> customers,
  }) {
    if (_loading && _data == null) {
      return const ShopSkeleton(
        semanticLabel: 'جارٍ تحميل الأرشيف...',
        child: ShopArchiveSkeleton(),
      );
    }
    if (_loadError != null && _data == null) {
      return _ArchiveLoadError(onRetry: _reload);
    }
    return Stack(
      children: [
        TabBarView(
          children: [
            _ArchiveList(
              key: const ValueKey('admin-archive-products-list'),
              onRefresh: _reload,
              emptyIcon: Icons.inventory_2_outlined,
              emptyTitle: _emptyTitle('منتجات'),
              children: [
                for (final product in products)
                  _ArchiveItemCard(
                    key: ValueKey('archived-product-${product.id}'),
                    icon: Icons.inventory_2_outlined,
                    title: product.name,
                    details: [
                      [
                        if (product.category.trim().isNotEmpty)
                          product.category.trim(),
                        if (product.sku.trim().isNotEmpty) product.sku.trim(),
                      ].join(' • '),
                      if (product.archivedAt != null)
                        'أُرشف في ${_dateLabel(product.archivedAt!)}',
                      if (product.archivedByCategoryId != null)
                        'أُرشف مع تصنيفه؛ استعد التصنيف لإرجاعه بأمان.',
                    ],
                    actionKey: ValueKey('restore-product-${product.id}'),
                    actionLabel: product.archivedByCategoryId == null
                        ? 'استعادة ونشر'
                        : 'استعد التصنيف أولاً',
                    busy: _busyItems.contains('product:${product.id}'),
                    onRestore: product.archivedByCategoryId == null
                        ? () => _restoreProduct(product)
                        : null,
                  ),
              ],
            ),
            _ArchiveList(
              key: const ValueKey('admin-archive-categories-list'),
              onRefresh: _reload,
              emptyIcon: Icons.category_outlined,
              emptyTitle: _emptyTitle('تصنيفات'),
              children: [
                for (final category in categories)
                  _ArchiveItemCard(
                    key: ValueKey('archived-category-${category.id}'),
                    icon: Icons.category_outlined,
                    leading: CategoryIconView.fromCategory(category, size: 22),
                    title: category.name,
                    details: [
                      category.archivedProductCount == 0
                          ? 'لا توجد منتجات مؤرشفة مع التصنيف'
                          : '${category.archivedProductCount} منتج مؤرشف مع التصنيف',
                      if (category.productCount > category.archivedProductCount)
                        'إجمالي المنتجات المرتبطة: ${category.productCount}',
                      if (category.archivedAt != null)
                        'أُرشف في ${_dateLabel(category.archivedAt!)}',
                    ],
                    actionKey: ValueKey('restore-category-${category.id}'),
                    actionLabel: 'استعادة التصنيف',
                    busy: _busyItems.contains('category:${category.id}'),
                    onRestore: () => _restoreCategory(category),
                  ),
              ],
            ),
            _ArchiveList(
              key: const ValueKey('admin-archive-customers-list'),
              onRefresh: _reload,
              emptyIcon: Icons.groups_outlined,
              emptyTitle: _emptyTitle('عملاء'),
              children: [
                for (final customer in customers)
                  _ArchiveItemCard(
                    key: ValueKey('archived-customer-${customer.id}'),
                    icon: Icons.store_outlined,
                    title: customer.businessName,
                    details: [
                      [
                        if (customer.username.trim().isNotEmpty)
                          customer.username.trim(),
                        if (customer.phone.trim().isNotEmpty)
                          customer.phone.trim(),
                        if (customer.city.trim().isNotEmpty)
                          customer.city.trim(),
                      ].join(' • '),
                    ],
                    actionKey: ValueKey('restore-customer-${customer.id}'),
                    actionLabel: 'استعادة وتفعيل',
                    busy: _busyItems.contains('customer:${customer.id}'),
                    onRestore: () => _restoreCustomer(customer),
                  ),
              ],
            ),
          ],
        ),
        if (_loading && _data != null)
          const PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  String _emptyTitle(String entity) => _query.trim().isEmpty
      ? 'لا توجد $entity مؤرشفة'
      : 'لا توجد نتائج مطابقة في $entity';

  Future<void> _restoreProduct(Product product) async {
    final confirmed = await _confirmRestore(
      title: 'استعادة المنتج',
      message:
          'سيعود «${product.name}» إلى قائمة المنتجات ويظهر للعملاء مجدداً.',
      confirmLabel: 'استعادة ونشر',
    );
    if (!confirmed) return;
    await _runRestore(
      key: 'product:${product.id}',
      action: () =>
          ref.read(catalogRepositoryProvider).restoreProduct(product.id),
      successMessage: 'تمت استعادة المنتج ونشره للعملاء.',
      failureMessage: 'تعذر استعادة المنتج. تحقق من الاتصال وحاول مجدداً.',
    );
  }

  Future<void> _restoreCategory(ProductCategory category) async {
    final confirmed = await _confirmRestore(
      title: 'استعادة التصنيف',
      message:
          'سيعود «${category.name}» والمنتجات التي أُرشفت معه إلى قائمة المنتجات.',
      confirmLabel: 'استعادة التصنيف',
    );
    if (!confirmed) return;
    await _runRestore(
      key: 'category:${category.id}',
      action: () =>
          ref.read(catalogRepositoryProvider).restoreCategory(category.id),
      successMessage: 'تمت استعادة التصنيف والمنتجات المرتبطة به.',
      failureMessage: 'تعذر استعادة التصنيف. تحقق من الاتصال وحاول مجدداً.',
    );
  }

  Future<void> _restoreCustomer(BusinessCustomer customer) async {
    final confirmed = await _confirmRestore(
      title: 'استعادة العميل',
      message:
          'سيعود «${customer.businessName}» نشطاً ويمكنه تسجيل الدخول والطلب.',
      confirmLabel: 'استعادة وتفعيل',
    );
    if (!confirmed) return;
    await _runRestore(
      key: 'customer:${customer.id}',
      action: () => ref.read(adminRepositoryProvider).saveCustomer(
            customer.copyWith(
              accountStatus: 'active',
            ),
          ),
      successMessage: 'تمت استعادة العميل وتفعيل حسابه.',
      failureMessage: 'تعذر استعادة العميل. تحقق من الاتصال وحاول مجدداً.',
    );
  }

  Future<bool> _confirmRestore({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runRestore({
    required String key,
    required Future<void> Function() action,
    required String successMessage,
    required String failureMessage,
  }) async {
    if (_busyItems.contains(key)) return;
    setState(() => _busyItems.add(key));
    try {
      try {
        await action();
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failureMessage)),
        );
        return;
      }
      if (!mounted) return;
      await reloadAfterMutation(this, _reload);
      if (!mounted) return;
      final refreshNotice = _loadError == null
          ? ''
          : ' تمت الاستعادة، لكن تعذر تحديث قائمة الأرشيف الآن. '
              'اضغط زر التحديث للمحاولة مجدداً.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successMessage$refreshNotice')),
      );
    } finally {
      if (mounted) setState(() => _busyItems.remove(key));
    }
  }
}

String _tabLabel(String label, int? count) =>
    count == null ? label : '$label ($count)';

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year}';
}

class _ArchiveData {
  const _ArchiveData({
    required this.products,
    required this.categories,
    required this.customers,
  });

  final List<Product> products;
  final List<ProductCategory> categories;
  final List<BusinessCustomer> customers;

  List<Product> matchingProducts(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return products;
    return products
        .where(
          (product) => [
            product.name,
            product.nameEn ?? '',
            product.sku,
            product.brand,
            product.category,
          ].any((value) => value.toLowerCase().contains(needle)),
        )
        .toList(growable: false);
  }

  List<ProductCategory> matchingCategories(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return categories;
    return categories
        .where((category) => category.name.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  List<BusinessCustomer> matchingCustomers(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return customers;
    return customers
        .where(
          (customer) => [
            customer.businessName,
            customer.username,
            customer.contactPerson,
            customer.phone,
            customer.city,
            customer.area,
          ].any((value) => value.toLowerCase().contains(needle)),
        )
        .toList(growable: false);
  }
}

class _ArchiveList extends StatelessWidget {
  const _ArchiveList({
    required this.onRefresh,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.children,
    super.key,
  });

  final Future<void> Function() onRefresh;
  final IconData emptyIcon;
  final String emptyTitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ShopRefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        children: children.isEmpty
            ? [
                SizedBox(
                  height: 260,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(emptyIcon, size: 52, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          emptyTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]
            : [
                for (final child in children) ...[
                  child,
                  const SizedBox(height: 10),
                ],
              ],
      ),
    );
  }
}

class _ArchiveItemCard extends StatelessWidget {
  const _ArchiveItemCard({
    required this.icon,
    required this.title,
    required this.details,
    required this.actionKey,
    required this.actionLabel,
    required this.busy,
    required this.onRestore,
    this.leading,
    super.key,
  });

  final IconData icon;
  final Widget? leading;
  final String title;
  final List<String> details;
  final Key actionKey;
  final String actionLabel;
  final bool busy;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final visibleDetails =
        details.where((detail) => detail.trim().isNotEmpty).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: Colors.blueGrey.shade700,
                  child: leading ?? Icon(icon),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      for (final detail in visibleDetails) ...[
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                key: actionKey,
                onPressed: busy ? null : onRestore,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore),
                label: Text(busy ? 'جارٍ الاستعادة...' : actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveLoadError extends StatelessWidget {
  const _ArchiveLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

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
              'تعذر تحميل الأرشيف',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'تحقق من الاتصال ثم أعد المحاولة.',
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

class _ArchiveRefreshErrorNotice extends StatelessWidget {
  const _ArchiveRefreshErrorNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('admin-archive-refresh-error'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem_outlined, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'تعذر تحديث الأرشيف. البيانات المعروضة قديمة؛ أعد المحاولة.',
              style: TextStyle(
                color: colors.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'إعادة تحديث الأرشيف',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            color: colors.onErrorContainer,
          ),
        ],
      ),
    );
  }
}
