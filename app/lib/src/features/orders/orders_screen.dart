import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/shop_branding.dart';
import '../../core/refresh/screen_reload.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/shop_loading.dart';
import '../../core/widgets/shop_refresh_indicator.dart';
import '../../core/widgets/shop_skeleton.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models/app_user.dart';
import '../../data/models/order.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../../data/sync/sync_outbox.dart';
import '../auth/auth_controller.dart';
import '../cart/cart_controller.dart';
import 'customer_invoice_actions.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({
    this.highlightedOrderId,
    this.showSuccessState = false,
    super.key,
  });

  final String? highlightedOrderId;
  final bool showSuccessState;

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  static const _pageSize = OrdersRepository.defaultPageSize;

  List<Order> orders = const [];
  String? loadedCustomerId;
  String? scheduledCustomerId;
  bool initialLoading = true;
  bool loadingMore = false;
  bool hasMore = false;
  Object? loadError;
  int nextOffset = 0;
  int loadRevision = 0;
  DateTime? snapshotAt;
  String? reorderingOrderId;
  bool successDismissed = false;

  @override
  void didUpdateWidget(covariant OrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightedOrderId != widget.highlightedOrderId &&
        loadedCustomerId != null) {
      unawaited(_reloadCustomer(loadedCustomerId!));
    }
    if (oldWidget.highlightedOrderId != widget.highlightedOrderId ||
        oldWidget.showSuccessState != widget.showSuccessState) {
      successDismissed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    listenForScreenReload(ref, _refresh);
    final user = ref.watch(authControllerProvider).user;
    final branding = ref.watch(shopBrandingProvider);
    final highlightedOrderId = widget.highlightedOrderId;
    if (user == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'انتهت جلسة الدخول. سجل الدخول من جديد لعرض الطلبات.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final queuedOrders = ref.watch(customerOrderOutboxProvider(user.id));
    final customerId = user.customerId ?? user.id;
    if (loadedCustomerId != customerId && scheduledCustomerId != customerId) {
      scheduledCustomerId = customerId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_reloadCustomer(customerId));
      });
    }
    final remoteLoading = initialLoading || loadedCustomerId != customerId;
    final visibleOrders =
        loadedCustomerId == customerId ? orders : const <Order>[];
    final successOrder =
        _resolveSuccessOrder(user: user, visibleOrders: visibleOrders);
    final localSnapshot = queuedOrders.asData?.value;

    final hasQueuedOrders = localSnapshot?.isEmpty == false;
    if (remoteLoading && !hasQueuedOrders && !queuedOrders.hasError) {
      return const _OrdersInitialSkeleton();
    }

    return ShopRefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'طلباتي',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: _refresh,
                tooltip: 'تحديث',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (successOrder != null) ...[
            _OrderSuccessPanel(
              order: successOrder,
              onViewOrder: () => setState(() => successDismissed = true),
              onBackToOrders: () {
                context.go(
                    '/orders?order=${Uri.encodeQueryComponent(successOrder.id)}');
              },
              shopName: branding.shopName,
              logoUrl: branding.logoUrl,
            ),
            const SizedBox(height: 12),
          ],
          queuedOrders.when(
            data: (queued) => queued.isEmpty
                ? const SizedBox.shrink()
                : _QueuedOrdersSection(
                    snapshot: queued,
                    onEdit: _discardAndEditQueuedOrder,
                  ),
            loading: () => const ShopSkeleton(
              semanticLabel: 'جارٍ فحص الطلبات غير المكتملة...',
              child: ShopSkeletonBox(
                height: 52,
                borderRadius: 14,
              ),
            ),
            error: (_, __) => const _OutboxReadErrorCard(),
          ),
          if (localSnapshot != null && !localSnapshot.isEmpty)
            const SizedBox(height: 16),
          if (remoteLoading)
            const _RemoteOrdersLoadingCard()
          else if (loadError != null)
            _OrdersErrorCard(onRetry: _refresh)
          else if (visibleOrders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: EmptyState(
                title: localSnapshot?.isEmpty == false
                    ? 'لا توجد طلبات معتمدة بعد'
                    : 'لا توجد طلبات',
                message: localSnapshot?.isEmpty == false
                    ? 'الطلبات المحفوظة أعلاه لم تعتمدها الإدارة بعد.'
                    : 'طلباتك المرسلة ستظهر هنا.',
                action: FilledButton(
                  onPressed: () => context.go('/catalog'),
                  child: const Text('ابدأ الطلب'),
                ),
              ),
            )
          else ...[
            for (final order in visibleOrders)
              _CustomerOrderCard(
                order: order,
                highlighted: order.id == highlightedOrderId,
                onReorder: reorderingOrderId == order.id
                    ? null
                    : () => _reorder(order),
                onCopy: () => _copySummary(
                  order,
                  branding.shopName,
                ),
                shopName: branding.shopName,
                logoUrl: branding.logoUrl,
              ),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                child: FilledButton.tonalIcon(
                  key: const ValueKey('customer-orders-load-more'),
                  onPressed: loadingMore ? null : _loadMore,
                  icon: loadingMore
                      ? const ShopLoading.compact()
                      : const Icon(Icons.expand_more),
                  label: Text(
                    loadingMore
                        ? 'جارٍ تحميل الطلبات الأقدم...'
                        : 'تحميل المزيد',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    final ownerProfileId = ref.read(authControllerProvider).user?.id;
    if (ownerProfileId != null) {
      ref.invalidate(customerOrderOutboxProvider(ownerProfileId));
    }
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    await _reloadCustomer(user.customerId ?? user.id);
  }

  Future<void> _reloadCustomer(String customerId) async {
    final revision = ++loadRevision;
    scheduledCustomerId = customerId;
    if (mounted) {
      setState(() {
        loadedCustomerId = customerId;
        initialLoading = true;
        loadingMore = false;
        loadError = null;
        orders = const [];
        hasMore = false;
        nextOffset = 0;
        snapshotAt = null;
      });
    }

    try {
      final repository = ref.read(ordersRepositoryProvider);
      final page = await repository.ordersPage(
        customerId: customerId,
        pageSize: _pageSize,
      );
      var loaded = page.orders;
      final highlightedId = widget.highlightedOrderId?.trim() ?? '';
      if (highlightedId.isNotEmpty &&
          !loaded.any((order) => order.id == highlightedId)) {
        try {
          final highlighted = await repository.orderById(
            highlightedId,
            customerId: customerId,
          );
          if (highlighted != null) {
            loaded = [highlighted, ...loaded];
          }
        } catch (_) {
          // Preserve the available page if the optional deep-link lookup fails.
        }
      }
      final currentUser = ref.read(authControllerProvider).user;
      final currentCustomerId = currentUser?.customerId ?? currentUser?.id;
      if (!mounted ||
          revision != loadRevision ||
          currentCustomerId != customerId) {
        return;
      }
      setState(() {
        orders = _deduplicateOrders(loaded);
        hasMore = page.hasMore;
        nextOffset = page.nextOffset;
        snapshotAt = page.snapshotAt;
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

  Future<void> _loadMore() async {
    final customerId = loadedCustomerId;
    final pageSnapshot = snapshotAt;
    if (customerId == null || pageSnapshot == null || loadingMore || !hasMore) {
      return;
    }
    final revision = loadRevision;
    setState(() => loadingMore = true);
    try {
      final page = await ref.read(ordersRepositoryProvider).ordersPage(
            customerId: customerId,
            snapshotAt: pageSnapshot,
            offset: nextOffset,
            pageSize: _pageSize,
          );
      if (!mounted || revision != loadRevision) return;
      setState(() {
        orders = _deduplicateOrders([...orders, ...page.orders]);
        hasMore = page.hasMore;
        nextOffset = page.nextOffset;
        loadingMore = false;
      });
    } catch (_) {
      if (!mounted || revision != loadRevision) return;
      setState(() => loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('تعذر تحميل الطلبات الأقدم. تحقق من الاتصال وحاول مجدداً.'),
        ),
      );
    }
  }

  Future<void> _discardAndEditQueuedOrder(
    SyncOutboxEntry entry,
    CustomerQueuedOrderState state,
  ) async {
    final isFailed = state == CustomerQueuedOrderState.failed;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isFailed ? 'حذف المحاولة الفاشلة؟' : 'إلغاء انتظار الإرسال؟',
        ),
        content: Text(
          isFailed
              ? 'هذه المحاولة لن تُرسل تلقائياً. سيُحذف سجلها المحلي فقط، '
                  'وستبقى السلة الحالية لتراجع الكميات والأسعار ثم ترسل طلباً جديداً.'
              : 'سيتم إلغاء الإرسال التلقائي لهذه المحاولة فقط، وستبقى '
                  'السلة الحالية لتعديلها ثم إرسال طلب جديد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              isFailed ? 'حذف وفتح السلة' : 'إلغاء الانتظار وفتح السلة',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final discarded = await ref
        .read(cartControllerProvider.notifier)
        .discardQueuedOrderForEditing(
          requestId: entry.id,
          expectedState: state,
        );
    if (!mounted) return;
    if (!discarded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تغيرت حالة المحاولة أو لم تعد محفوظة. حدّث الطلبات قبل المتابعة.',
          ),
        ),
      );
      ref.invalidate(
        customerOrderOutboxProvider(
          ref.read(authControllerProvider).user?.id ?? '',
        ),
      );
      return;
    }
    requestScreenReload(ref);
    context.go('/cart');
  }

  Future<void> _reorder(Order order) async {
    if (reorderingOrderId != null) return;
    setState(() => reorderingOrderId = order.id);
    var added = 0;
    var unavailable = 0;
    var adjusted = 0;
    try {
      final catalog = ref.read(catalogRepositoryProvider);
      final cart = ref.read(cartControllerProvider.notifier);
      for (final item in order.items) {
        final current = await catalog.productById(item.productId);
        if (current == null ||
            !current.active ||
            current.isArchived ||
            !current.isOrderable) {
          unavailable++;
          continue;
        }
        final quantity = current.normalizeOrderQuantity(item.quantity);
        if (quantity != item.quantity) adjusted++;
        cart.addQuantity(current, quantity);
        added++;
      }

      if (!mounted) return;
      if (added == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('منتجات هذا الطلب غير متاحة حالياً لإضافتها من جديد.'),
          ),
        );
        return;
      }
      if (unavailable > 0 || adjusted > 0) {
        final parts = <String>[
          if (unavailable > 0) 'تعذر إضافة $unavailable منتج',
          if (adjusted > 0)
            'تم تعديل كمية $adjusted منتج حسب المخزون والحد الأدنى',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${parts.join('، ')}.')),
        );
      }
      requestScreenReload(ref);
      context.go('/cart');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر التحقق من الأسعار والمخزون الحاليين. تحقق من الاتصال وحاول مجدداً.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => reorderingOrderId = null);
    }
  }

  Future<void> _copySummary(Order order, String businessName) async {
    final summary =
        ref.read(ordersRepositoryProvider).whatsappSummary(order, businessName);
    await Clipboard.setData(ClipboardData(text: summary));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ ملخص الطلب')),
      );
    }
  }

  Order? _resolveSuccessOrder({
    required AppUser user,
    required List<Order> visibleOrders,
  }) {
    if (!widget.showSuccessState || successDismissed) return null;
    final highlightedId = widget.highlightedOrderId?.trim();
    if (highlightedId == null || highlightedId.isEmpty) return null;
    final expectedCustomerId = user.customerId ?? user.id;
    for (final order in visibleOrders) {
      if (order.id == highlightedId && order.customerId == expectedCustomerId) {
        return order;
      }
    }
    return null;
  }
}

class _OrdersInitialSkeleton extends StatelessWidget {
  const _OrdersInitialSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('orders-initial-skeleton'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        ShopSkeleton(
          semanticLabel: 'جارٍ تحميل الطلبات',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ShopSkeletonBox(
                        width: 104,
                        height: 28,
                        borderRadius: 9,
                      ),
                    ),
                  ),
                  ShopSkeletonCircle(size: 44),
                ],
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < 4; index++)
                _OrderSkeletonCard(index: index),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderSkeletonCard extends StatelessWidget {
  const _OrderSkeletonCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('orders-skeleton-card-$index'),
      margin: const EdgeInsets.only(bottom: 12),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            ShopSkeletonBox(
              width: 48,
              height: 48,
              borderRadius: 12,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ShopSkeletonBox(height: 16, borderRadius: 7),
                  SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: .72,
                    alignment: AlignmentDirectional.centerStart,
                    child: ShopSkeletonBox(height: 11, borderRadius: 6),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            ShopSkeletonBox(
              width: 58,
              height: 28,
              borderRadius: 999,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderSuccessPanel extends StatelessWidget {
  const _OrderSuccessPanel({
    required this.order,
    required this.onViewOrder,
    required this.onBackToOrders,
    required this.shopName,
    this.logoUrl,
  });

  final Order order;
  final VoidCallback onViewOrder;
  final VoidCallback onBackToOrders;
  final String shopName;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('orders-success-panel'),
      color: scheme.primaryContainer.withValues(alpha: .45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                _SuccessCelebrationIcon(),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تم استلام طلبك بنجاح!',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'شكراً لطلبك 🤍 سنقوم بمراجعته وتحديث حالته قريباً.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text('رقم الطلب: ${order.displayNumber}'),
            const SizedBox(height: 2),
            Text(
              'الإجمالي المعتمد: ${lyd(order.total)}',
              key: const ValueKey('orders-success-total'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('orders-success-view-order'),
                  onPressed: onViewOrder,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('عرض الطلب'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('orders-success-download-pdf'),
                  onPressed: () => CustomerInvoiceActions.downloadPdfForOrder(
                    context,
                    order: order,
                    shopName: shopName,
                    logoUrl: logoUrl,
                  ),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('تحميل الفاتورة PDF'),
                ),
                TextButton(
                  key: const ValueKey('orders-success-back'),
                  onPressed: onBackToOrders,
                  child: const Text('العودة إلى طلباتي'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessCelebrationIcon extends StatefulWidget {
  const _SuccessCelebrationIcon();

  @override
  State<_SuccessCelebrationIcon> createState() =>
      _SuccessCelebrationIconState();
}

class _SuccessCelebrationIconState extends State<_SuccessCelebrationIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, .65, curve: Curves.easeOut),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                painter: _BurstPainter(progress: _fade.value),
                size: const Size.square(52),
              ),
              Opacity(
                opacity: .7 + (_fade.value * .3),
                child: Transform.scale(
                  scale: .88 + (_scale.value * .12),
                  child: const Icon(
                    Icons.check_circle,
                    color: Color(0xff1d8f52),
                    size: 34,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    const count = 10;
    final center = size.center(Offset.zero);
    final radius = 14 + (progress * 11);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xff8cd9af).withValues(alpha: 1 - progress);
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 6.28318530718;
      final dot = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawCircle(dot, 2.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _QueuedOrdersSection extends StatelessWidget {
  const _QueuedOrdersSection({
    required this.snapshot,
    required this.onEdit,
  });

  final CustomerOrderOutboxSnapshot snapshot;
  final Future<void> Function(
    SyncOutboxEntry entry,
    CustomerQueuedOrderState state,
  ) onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'طلبات محفوظة على هذا الجهاز',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'هذه المحاولات تخص حسابك الحالي فقط، وليست طلبات معتمدة حتى يظهر لها رقم طلب رسمي.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 10),
        for (final entry in snapshot.pending)
          _QueuedOrderCard(
            entry: entry,
            state: CustomerQueuedOrderState.pending,
            onEdit: () => onEdit(
              entry,
              CustomerQueuedOrderState.pending,
            ),
          ),
        for (final entry in snapshot.failed)
          _QueuedOrderCard(
            entry: entry,
            state: CustomerQueuedOrderState.failed,
            onEdit: () => onEdit(
              entry,
              CustomerQueuedOrderState.failed,
            ),
          ),
      ],
    );
  }
}

class _QueuedOrderCard extends StatelessWidget {
  const _QueuedOrderCard({
    required this.entry,
    required this.state,
    required this.onEdit,
  });

  final SyncOutboxEntry entry;
  final CustomerQueuedOrderState state;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isFailed = state == CustomerQueuedOrderState.failed;
    final colors = Theme.of(context).colorScheme;
    final details = _queuedOrderDetails(entry);
    return Card(
      color: isFailed ? colors.errorContainer : colors.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isFailed ? Icons.error_outline : Icons.cloud_upload_outlined,
                  color: isFailed
                      ? colors.onErrorContainer
                      : colors.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isFailed
                            ? 'تعذر اعتماد طلب محفوظ'
                            : 'بانتظار الإرسال التلقائي',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isFailed
                            ? queuedOrderFailureMessage(entry.errorCode)
                            : 'لم يصل هذا الطلب إلى الإدارة بعد. سيحاول التطبيق '
                                'إرساله تلقائياً عند توفر الاتصال.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              details,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'مرجع محلي: ${_shortReference(entry.id)}',
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                onPressed: onEdit,
                icon: Icon(
                  isFailed ? Icons.edit_note_outlined : Icons.edit_outlined,
                ),
                label: Text(
                  isFailed
                      ? 'حذف المحاولة ومراجعة السلة'
                      : 'إلغاء الانتظار ومراجعة السلة',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutboxReadErrorCard extends StatelessWidget {
  const _OutboxReadErrorCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.storage_outlined),
        title: Text('تعذر قراءة الطلبات المحفوظة محلياً'),
        subtitle: Text('أعد فتح صفحة الطلبات قبل إرسال طلب جديد.'),
      ),
    );
  }
}

class _RemoteOrdersLoadingCard extends StatelessWidget {
  const _RemoteOrdersLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: ShopLoading.compact(size: 20),
        title: Text('جارٍ تحميل الطلبات المعتمدة...'),
      ),
    );
  }
}

class _CustomerOrderCard extends StatelessWidget {
  const _CustomerOrderCard({
    required this.order,
    required this.highlighted,
    required this.onReorder,
    required this.onCopy,
    this.shopName = '',
    this.logoUrl,
  });

  final Order order;
  final bool highlighted;
  final VoidCallback? onReorder;
  final VoidCallback onCopy;
  final String shopName;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: highlighted
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              )
            : BorderSide.none,
      ),
      child: ExpansionTile(
        initiallyExpanded: highlighted,
        leading: order.items.isEmpty
            ? null
            : SizedBox.square(
                dimension: 48,
                child: ProductImagePlaceholder(
                  key: ValueKey(
                    'customer-order-preview-image-${order.id}',
                  ),
                  category: order.items.first.product.category,
                  productId: order.items.first.productId,
                  imageUrl: order.items.first.product.imageUrl,
                  expand: true,
                  fit: BoxFit.contain,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
        title: Text(
          'طلب ${order.displayNumber}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${_date(order.createdAt)} • ${order.items.length} منتجات • ${lyd(order.total)}',
        ),
        trailing: StatusChip.order(order.status),
        children: [
          for (final item in order.items)
            _CustomerOrderProductRow(
              orderId: order.id,
              item: item,
            ),
          const Divider(height: 1),
          _OrderTotalTile(
            label: 'الإجمالي الفرعي',
            amount: order.subtotal,
          ),
          if (order.deliveryFee > 0)
            _OrderTotalTile(label: 'التوصيل', amount: order.deliveryFee),
          if (order.handlingFee > 0)
            _OrderTotalTile(label: 'المناولة', amount: order.handlingFee),
          _OrderTotalTile(
            label: 'الإجمالي المعتمد',
            amount: order.total,
            bold: true,
          ),
          if (order.deliveryAddress.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('عنوان التسليم'),
              subtitle: Text(order.deliveryAddress),
            ),
          if (order.customerNote.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('ملاحظة العميل'),
              subtitle: Text(order.customerNote),
            ),
          if (order.adminNote.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('ملاحظة الإدارة'),
              subtitle: Text(order.adminNote),
            ),
          _OrderHistory(order: order),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: OverflowBar(
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onReorder,
                  icon: const Icon(Icons.replay),
                  label: const Text('إعادة الطلب'),
                ),
                TextButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy),
                  label: const Text('نسخ ملخص واتساب'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
                start: 12, end: 12, bottom: 14),
            child: CustomerInvoiceActions(
              order: order,
              shopName: shopName.isEmpty ? order.businessName : shopName,
              logoUrl: logoUrl,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerOrderProductRow extends StatelessWidget {
  const _CustomerOrderProductRow({
    required this.orderId,
    required this.item,
  });

  final String orderId;
  final OrderLine item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 58,
            child: ProductImagePlaceholder(
              key: ValueKey(
                'customer-order-item-image-$orderId-${item.productId}',
              ),
              category: item.product.category,
              productId: item.productId,
              imageUrl: item.product.imageUrl,
              expand: true,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    '${item.quantity} × ${lyd(item.unitPrice)}',
                    if (item.unitsPerBox != null)
                      '${item.unitsPerBox} قطعة في الصندوق',
                  ].join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .66),
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            lyd(item.lineTotal),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderHistory extends StatelessWidget {
  const _OrderHistory({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    if (order.statusHistory.isEmpty) {
      return ListTile(
        leading: const Icon(Icons.timeline),
        title: const Text('الحالة الحالية'),
        subtitle: Text(order.status.label),
      );
    }
    return ExpansionTile(
      leading: const Icon(Icons.timeline),
      title: const Text('مسار الحالة'),
      children: [
        for (final entry in order.statusHistory)
          ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle_outline, size: 20),
            title: Text(entry.toStatus.label),
            subtitle: Text(
              [
                _dateTime(entry.changedAt),
                if (entry.note.isNotEmpty) entry.note,
              ].join(' • '),
            ),
          ),
      ],
    );
  }
}

class _OrderTotalTile extends StatelessWidget {
  const _OrderTotalTile({
    required this.label,
    required this.amount,
    this.bold = false,
  });

  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style =
        TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            lyd(amount),
            maxLines: 1,
            style: style,
          ),
        ],
      ),
    );
  }
}

class _OrdersErrorCard extends StatelessWidget {
  const _OrdersErrorCard({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 46,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 10),
            const Text(
              'تعذر تحميل الطلبات المعتمدة حالياً',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 6),
            const Text(
              'تبقى الطلبات المحلية أعلاه محفوظة. تحقق من الاتصال ثم حاول من جديد.',
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

String queuedOrderFailureMessage(String? errorCode) {
  switch (errorCode?.trim().toUpperCase()) {
    case 'OUT_OF_STOCK':
    case 'INSUFFICIENT_STOCK':
      return 'تغير المخزون ولن يعاد إرسال هذه المحاولة تلقائياً. راجع الكميات في السلة.';
    case 'PRODUCT_UNAVAILABLE':
    case 'PRODUCT_NOT_FOUND':
      return 'أحد المنتجات لم يعد متاحاً. احذف المحاولة وراجع السلة قبل إرسال طلب جديد.';
    case 'MINIMUM_QUANTITY':
    case 'MINIMUM_QUANTITY_NOT_MET':
    case 'MOQ_NOT_MET':
      return 'إحدى الكميات أقل من الحد الأدنى الحالي. راجع السلة ثم أرسل طلباً جديداً.';
    case 'MINIMUM_ORDER_NOT_MET':
    case 'MINIMUM_ORDER_AMOUNT_NOT_MET':
      return 'قيمة الطلب أقل من الحد الأدنى الحالي. راجع السلة قبل المحاولة من جديد.';
    case 'PRICE_CHANGED':
    case 'PRODUCT_PRICE_UNAVAILABLE':
      return 'تعذر اعتماد سعر أحد المنتجات. راجع الأسعار الحالية قبل إرسال طلب جديد.';
    case 'UNAUTHORIZED':
    case 'AUTH_REQUIRED':
    case 'INVALID_TOKEN':
      return 'انتهت جلسة الدخول أثناء الإرسال. سجل الدخول من جديد وراجع السلة.';
    case 'FORBIDDEN':
    case 'ACCOUNT_INACTIVE':
    case 'CUSTOMER_ACCOUNT_INACTIVE':
    case 'PROFILE_INACTIVE':
    case 'CUSTOMER_SUSPENDED':
      return 'الحساب غير مخول لإرسال الطلب. تواصل مع الإدارة قبل إعادة المحاولة.';
    case 'DUPLICATE_REQUEST':
    case 'IDEMPOTENCY_CONFLICT':
      return 'تعارضت هذه المحاولة مع طلب سابق. حدّث الطلبات وراجع السلة.';
    case 'INVALID_OUTBOX_PAYLOAD':
    case 'INVALID_CLIENT_REQUEST_ID':
    case 'INVALID_QUANTITY':
    case 'EMPTY_ORDER':
      return 'النسخة المحلية غير مكتملة ولن تُرسل تلقائياً. احذفها وراجع السلة.';
    case 'UNEXPECTED_RETRY_FAILURE':
    case 'UNEXPECTED_LOCAL_FAILURE':
      return 'حدث خطأ غير متوقع أثناء الإرسال. احذف المحاولة وراجع السلة قبل طلب جديد.';
    default:
      return 'تعذر اعتماد هذه المحاولة ولن يعاد إرسالها تلقائياً. راجع السلة ثم أرسل طلباً جديداً.';
  }
}

String _queuedOrderDetails(SyncOutboxEntry entry) {
  final rawItems = entry.payload['items'];
  var itemKinds = 0;
  var totalQuantity = 0;
  if (rawItems is List) {
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final productId = rawItem['product_id']?.toString().trim() ?? '';
      final rawQuantity = rawItem['quantity'];
      final quantity = rawQuantity is num
          ? rawQuantity.toInt()
          : int.tryParse(rawQuantity?.toString() ?? '') ?? 0;
      if (productId.isEmpty || quantity <= 0) continue;
      itemKinds++;
      totalQuantity += quantity;
    }
  }
  final address = entry.payload['delivery_address']?.toString().trim() ?? '';
  return [
    'عدد الأصناف: $itemKinds',
    'مجموع الكمية: $totalQuantity',
    if (address.isNotEmpty) 'العنوان: $address',
  ].join(' • ');
}

String _shortReference(String id) {
  final normalized = id.trim();
  if (normalized.isEmpty) return 'غير متوفر';
  if (normalized.length <= 8) return normalized;
  return normalized.substring(normalized.length - 8);
}

String _date(DateTime date) => '${date.year}/${date.month}/${date.day}';

String _dateTime(DateTime date) =>
    '${_date(date)} ${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

List<Order> _deduplicateOrders(Iterable<Order> source) {
  final seen = <String>{};
  return [
    for (final order in source)
      if (seen.add(order.id)) order,
  ];
}
