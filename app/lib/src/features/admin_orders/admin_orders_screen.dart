import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/order_status.dart';
import '../../core/notifications/new_order_alert_sound.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models/order.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../admin_dashboard/admin_shell.dart';

class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({
    this.highlightedOrderId,
    this.showTodayOnly = false,
    this.autoRefreshInterval = const Duration(seconds: 20),
    super.key,
  });

  final String? highlightedOrderId;
  final bool showTodayOnly;
  final Duration autoRefreshInterval;

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen>
    with WidgetsBindingObserver {
  static const _pageSize = OrdersRepository.defaultPageSize;

  OrderStatus? filter;
  late bool todayOnly;
  late bool soundEnabled;
  late bool soundReady;
  List<Order> orders = const [];
  bool initialLoading = true;
  bool refreshing = false;
  bool manualRefreshStarting = false;
  bool soundToggleBusy = false;
  bool loadingMore = false;
  bool hasMore = false;
  Object? loadError;
  int nextOffset = 0;
  int loadRevision = 0;
  DateTime? snapshotAt;
  DateTime? lastUpdatedAt;
  String? updatingOrderId;
  Timer? autoRefreshTimer;
  bool appIsResumed = true;
  bool hasAttemptedInitialLoad = false;
  bool hasLoadedOnce = false;
  bool hasNewOrderNotificationBaseline = false;
  bool hasOrderBaseline = false;
  bool soundBlockedHintShown = false;
  final Set<String> seenNewOrderNotificationIds = {};
  final Set<String> seenOrderIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    appIsResumed =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    todayOnly = widget.highlightedOrderId == null && widget.showTodayOnly;
    final sound = ref.read(newOrderAlertSoundProvider);
    soundEnabled = sound.isAvailable;
    soundReady = sound.isAvailable && !kIsWeb;
    _startAutoRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_reload(showFullLoading: true));
      }
    });
  }

  @override
  void didUpdateWidget(covariant AdminOrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoRefreshInterval != widget.autoRefreshInterval) {
      _startAutoRefresh();
    }
    if (oldWidget.showTodayOnly != widget.showTodayOnly ||
        oldWidget.highlightedOrderId != widget.highlightedOrderId) {
      todayOnly = widget.highlightedOrderId == null && widget.showTodayOnly;
      unawaited(_reload(showFullLoading: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appIsResumed = state == AppLifecycleState.resumed;
    if (appIsResumed) {
      _startAutoRefresh();
      if (hasLoadedOnce && !_backgroundRefreshBlocked) {
        unawaited(
          _reload(consumeNewOrdersWithoutAnnouncement: true),
        );
      }
      return;
    }
    autoRefreshTimer?.cancel();
  }

  @override
  void dispose() {
    autoRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlightedOrderId = widget.highlightedOrderId;
    final soundAvailable = ref.watch(newOrderAlertSoundProvider).isAvailable;
    return AdminShell(
      title: 'إدارة الطلبات',
      actions: [
        IconButton(
          key: const ValueKey('refresh-admin-orders-button'),
          onPressed: _backgroundRefreshBlocked
              ? null
              : () => unawaited(_manualRefresh()),
          icon: refreshing || manualRefreshStarting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: 'تحديث الطلبات الآن',
        ),
        if (soundAvailable)
          IconButton(
            key: const ValueKey('toggle-admin-orders-sound-button'),
            onPressed: soundToggleBusy ? null : () => unawaited(_toggleSound()),
            icon: Icon(
              !soundEnabled
                  ? Icons.volume_off_outlined
                  : soundReady
                      ? Icons.volume_up
                      : Icons.volume_up_outlined,
            ),
            tooltip: !soundEnabled
                ? 'تشغيل صوت الطلبات الجديدة'
                : soundReady
                    ? 'إيقاف صوت الطلبات الجديدة'
                    : 'اضغط لتفعيل صوت الطلبات الجديدة',
          ),
      ],
      child: initialLoading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null && orders.isEmpty
              ? _AdminOrdersError(onRetry: _manualRefresh)
              : RefreshIndicator(
                  onRefresh: _manualRefresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    children: [
                      _OrdersLiveStatus(
                        autoRefreshInterval: widget.autoRefreshInterval,
                        refreshing: refreshing,
                        lastUpdatedAt: lastUpdatedAt,
                        refreshFailed: loadError != null,
                        soundAvailable: soundAvailable,
                        soundEnabled: soundEnabled,
                        soundReady: soundReady,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('كل الأيام'),
                            selected: !todayOnly,
                            onSelected: (_) => _setTodayOnly(false),
                          ),
                          ChoiceChip(
                            label: const Text('اليوم'),
                            selected: todayOnly,
                            onSelected: (_) => _setTodayOnly(true),
                          ),
                          ChoiceChip(
                            label: const Text('كل الحالات'),
                            selected: filter == null,
                            onSelected: (_) => _setFilter(null),
                          ),
                          for (final status in OrderStatus.values)
                            ChoiceChip(
                              label: Text(status.label),
                              selected: filter == status,
                              onSelected: (_) => _setFilter(status),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        hasMore
                            ? 'المعروض حالياً: ${orders.length} طلب — توجد طلبات أقدم'
                            : 'المعروض حالياً: ${orders.length} طلب',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      if (orders.isEmpty)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.receipt_long),
                            title: Text('لا توجد طلبات بهذا الفلتر'),
                          ),
                        )
                      else
                        for (final order in orders)
                          _AdminOrderCard(
                            order: order,
                            highlighted: order.id == highlightedOrderId,
                            updating: updatingOrderId == order.id,
                            onChangeStatus: () => _showStatusDialog(order),
                            onCopy: () => _copySummary(order),
                          ),
                      if (hasMore)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 20),
                          child: FilledButton.tonalIcon(
                            key: const ValueKey('admin-orders-load-more'),
                            onPressed: loadingMore ? null : _loadMore,
                            icon: loadingMore
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.expand_more),
                            label: Text(
                              loadingMore
                                  ? 'جارٍ تحميل الطلبات الأقدم...'
                                  : 'تحميل المزيد',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  bool get _backgroundRefreshBlocked =>
      initialLoading ||
      refreshing ||
      manualRefreshStarting ||
      loadingMore ||
      updatingOrderId != null;

  void _setTodayOnly(bool value) {
    if (todayOnly == value) return;
    setState(() => todayOnly = value);
    unawaited(_reload(showFullLoading: true));
  }

  void _setFilter(OrderStatus? value) {
    if (filter == value) return;
    setState(() => filter = value);
    unawaited(_reload(showFullLoading: true));
  }

  ({DateTime? from, DateTime? until}) _dateRange() {
    if (!todayOnly) return (from: null, until: null);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return (
      from: start.toUtc(),
      until: start.add(const Duration(days: 1)).toUtc(),
    );
  }

  Future<void> _reload({
    bool announceNewOrders = false,
    bool consumeNewOrdersWithoutAnnouncement = false,
    bool showFullLoading = false,
    bool showFeedback = false,
  }) async {
    if (!showFullLoading && (initialLoading || refreshing || loadingMore)) {
      return;
    }
    final revision = ++loadRevision;
    final range = _dateRange();
    final showBlockingLoading = showFullLoading || !hasAttemptedInitialLoad;
    hasAttemptedInitialLoad = true;
    if (mounted) {
      setState(() {
        loadingMore = false;
        if (showBlockingLoading) {
          loadError = null;
          initialLoading = true;
          refreshing = false;
          orders = const [];
          hasMore = false;
          nextOffset = 0;
          snapshotAt = null;
        } else {
          refreshing = true;
        }
      });
    }

    try {
      final notificationIds = await _latestNewOrderNotificationIds();
      final repository = ref.read(ordersRepositoryProvider);
      final page = await repository.ordersPage(
        status: filter,
        createdFrom: range.from,
        createdUntil: range.until,
        pageSize: _pageSize,
      );
      var loaded = page.orders;
      final highlightedId = widget.highlightedOrderId?.trim() ?? '';
      if (highlightedId.isNotEmpty &&
          filter == null &&
          !todayOnly &&
          !loaded.any((order) => order.id == highlightedId)) {
        try {
          final highlighted = await repository.orderById(highlightedId);
          if (highlighted != null) {
            loaded = [highlighted, ...loaded];
          }
        } catch (_) {
          // The main bounded page is still useful if deep-link lookup fails.
        }
      }
      final deduplicated = _deduplicateOrders(loaded);
      if (!mounted || revision != loadRevision) return;

      final newOrderIds = <String>{};
      if (notificationIds != null) {
        if (!hasNewOrderNotificationBaseline) {
          seenNewOrderNotificationIds.addAll(notificationIds);
          hasNewOrderNotificationBaseline = true;
        } else if (announceNewOrders || consumeNewOrdersWithoutAnnouncement) {
          if (announceNewOrders) {
            newOrderIds.addAll(
              notificationIds.difference(seenNewOrderNotificationIds),
            );
          }
          seenNewOrderNotificationIds.addAll(notificationIds);
        }
      }

      final loadedOrderIds = {
        for (final order in deduplicated) order.id,
      };
      if (AppConfig.isDemoMode &&
          (notificationIds == null || notificationIds.isEmpty) &&
          hasOrderBaseline &&
          announceNewOrders) {
        newOrderIds.addAll(loadedOrderIds.difference(seenOrderIds));
      }
      seenOrderIds.addAll(loadedOrderIds);
      hasOrderBaseline = true;

      setState(() {
        orders = deduplicated;
        hasMore = page.hasMore;
        nextOffset = page.nextOffset;
        snapshotAt = page.snapshotAt;
        loadError = null;
        initialLoading = false;
        refreshing = false;
        hasLoadedOnce = true;
        lastUpdatedAt = DateTime.now();
      });
      if (newOrderIds.isNotEmpty) {
        ref.invalidate(unreadNotificationsCountProvider);
        await _announceNewOrders(newOrderIds.length);
      } else if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث الطلبات — لا توجد طلبات جديدة.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted || revision != loadRevision) return;
      setState(() {
        loadError = error;
        initialLoading = false;
        refreshing = false;
      });
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر تحديث الطلبات. ستستمر المحاولة تلقائياً عند عودة الاتصال.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    final pageSnapshot = snapshotAt;
    if (loadingMore || !hasMore || pageSnapshot == null) return;
    final revision = loadRevision;
    final range = _dateRange();
    setState(() => loadingMore = true);
    try {
      final page = await ref.read(ordersRepositoryProvider).ordersPage(
            status: filter,
            createdFrom: range.from,
            createdUntil: range.until,
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

  Future<void> _manualRefresh() async {
    if (_backgroundRefreshBlocked) return;
    setState(() => manualRefreshStarting = true);
    try {
      await _primeSoundFromGesture();
      await _reload(
        announceNewOrders: true,
        showFullLoading: !hasLoadedOnce && orders.isEmpty,
        showFeedback: true,
      );
    } finally {
      if (mounted) setState(() => manualRefreshStarting = false);
    }
  }

  void _startAutoRefresh() {
    autoRefreshTimer?.cancel();
    if (!appIsResumed || widget.autoRefreshInterval <= Duration.zero) return;
    autoRefreshTimer = Timer.periodic(
      widget.autoRefreshInterval,
      (_) {
        if (!mounted || _backgroundRefreshBlocked) return;
        unawaited(_reload(announceNewOrders: true));
      },
    );
  }

  Future<Set<String>?> _latestNewOrderNotificationIds() async {
    try {
      final notifications = await ref
          .read(notificationsRepositoryProvider)
          .list(limit: 50)
          .timeout(const Duration(seconds: 6));
      return {
        for (final notification in notifications)
          if (notification.type == 'new_order') notification.id,
      };
    } catch (_) {
      // Order refresh remains useful if the notification feed is unavailable.
      return null;
    }
  }

  Future<void> _primeSoundFromGesture() async {
    if (!soundEnabled) return;
    final ready = await ref.read(newOrderAlertSoundProvider).prime();
    if (!mounted) return;
    setState(() {
      soundReady = ready;
      if (ready) soundBlockedHintShown = false;
    });
  }

  Future<void> _toggleSound() async {
    final sound = ref.read(newOrderAlertSoundProvider);
    if (!sound.isAvailable || soundToggleBusy) return;

    setState(() => soundToggleBusy = true);
    try {
      if (soundEnabled && soundReady) {
        setState(() => soundEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إيقاف صوت الطلبات الجديدة.')),
        );
        return;
      }

      if (!soundEnabled) {
        setState(() => soundEnabled = true);
      }
      final ready = await sound.prime();
      final played = ready && await sound.play();
      if (!mounted) return;
      setState(() {
        soundReady = ready && played;
        soundBlockedHintShown = !soundReady;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            soundReady
                ? 'تم تشغيل صوت الطلبات الجديدة.'
                : 'تعذر تشغيل الصوت. تحقق من كتم الجهاز ثم اضغط رمز الصوت مجدداً.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => soundToggleBusy = false);
    }
  }

  Future<void> _announceNewOrders(int count) async {
    if (!appIsResumed) return;
    final sound = ref.read(newOrderAlertSoundProvider);
    var played = false;
    if (soundEnabled && sound.isAvailable) {
      played = await sound.play();
    }
    if (!mounted || !appIsResumed) return;

    final shouldOfferSoundAction =
        soundEnabled && sound.isAvailable && !played && !soundBlockedHintShown;
    final filteredView = filter != null || todayOnly;
    setState(() {
      if (soundEnabled && sound.isAvailable) {
        soundReady = played;
      }
      if (shouldOfferSoundAction) soundBlockedHintShown = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 1
              ? filteredView
                  ? 'وصل طلب جديد. قد لا يظهر مع الفلتر الحالي.'
                  : 'وصل طلب جديد وتم تحديث القائمة.'
              : filteredView
                  ? 'وصلت $count طلبات جديدة. قد لا تظهر كلها مع الفلتر الحالي.'
                  : 'وصلت $count طلبات جديدة وتم تحديث القائمة.',
        ),
        action: shouldOfferSoundAction
            ? SnackBarAction(
                label: 'تفعيل الصوت',
                onPressed: () => unawaited(_toggleSound()),
              )
            : null,
      ),
    );
  }

  Future<void> _showStatusDialog(Order order) async {
    if (order.allowedNextStatuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            order.status == OrderStatus.delivered
                ? 'الطلب مسلّم ولا توجد حالة تالية.'
                : 'الطلب ملغي ولا يمكن تغيير حالته.',
          ),
        ),
      );
      return;
    }

    var selected = order.allowedNextStatuses.first;
    final note = TextEditingController();
    final update = await showDialog<_StatusUpdate>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('تغيير حالة الطلب ${order.displayNumber}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('الحالة الحالية: ${order.status.label}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<OrderStatus>(
                  initialValue: selected,
                  decoration:
                      const InputDecoration(labelText: 'الحالة التالية'),
                  items: [
                    for (final status in order.allowedNextStatuses)
                      DropdownMenuItem(
                        value: status,
                        child: Text(status.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selected = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة الإدارة (اختيارية)',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'سيُحفظ تغيير الحالة في السجل ويُستخدم لإشعار العميل.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _StatusUpdate(status: selected, note: note.text.trim()),
              ),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    note.dispose();
    if (update == null || !mounted) return;

    setState(() => updatingOrderId = order.id);
    try {
      await ref.read(ordersRepositoryProvider).transitionOrderStatus(
            order.id,
            update.status,
            adminNote: update.note,
          );
      if (AppConfig.isDemoMode) {
        ref.read(notificationsRepositoryProvider).addDemoOrderStatus(
              orderId: order.id,
              statusLabel: update.status.label,
            );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحديث الطلب إلى: ${update.status.label}'),
        ),
      );
      await _reload();
    } on OrdersRepositoryException catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديث حالة الطلب. حدّث القائمة وحاول مجدداً.'),
        ),
      );
    } finally {
      if (mounted) setState(() => updatingOrderId = null);
    }
  }

  Future<void> _copySummary(Order order) async {
    final summary = ref.read(ordersRepositoryProvider).whatsappSummary(
          order,
          order.businessName.isEmpty ? 'عميل B2B' : order.businessName,
        );
    await Clipboard.setData(ClipboardData(text: summary));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ ملخص الطلب')),
      );
    }
  }
}

class _OrdersLiveStatus extends StatelessWidget {
  const _OrdersLiveStatus({
    required this.autoRefreshInterval,
    required this.refreshing,
    required this.lastUpdatedAt,
    required this.refreshFailed,
    required this.soundAvailable,
    required this.soundEnabled,
    required this.soundReady,
  });

  final Duration autoRefreshInterval;
  final bool refreshing;
  final DateTime? lastUpdatedAt;
  final bool refreshFailed;
  final bool soundAvailable;
  final bool soundEnabled;
  final bool soundReady;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = refreshFailed ? scheme.error : scheme.primary;
    final refreshLabel = refreshing
        ? 'جارٍ جلب أحدث الطلبات...'
        : refreshFailed
            ? 'تعذر آخر تحديث — ستتم المحاولة تلقائياً'
            : lastUpdatedAt == null
                ? 'الاتصال المباشر بالطلبات'
                : 'آخر تحديث ${_shortTime(lastUpdatedAt!)}';
    final intervalLabel = autoRefreshInterval <= Duration.zero
        ? 'التحديث التلقائي متوقف'
        : 'تحديث تلقائي ${_durationLabel(autoRefreshInterval)}';
    final soundLabel = !soundEnabled
        ? 'صوت الطلبات متوقف'
        : soundReady
            ? 'صوت الطلبات مفعّل'
            : 'اضغط رمز الصوت مرة واحدة لتفعيله';

    return Container(
      key: const ValueKey('admin-orders-live-status'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OrdersStatusLabel(
            icon: refreshing
                ? Icons.sync
                : refreshFailed
                    ? Icons.sync_problem_outlined
                    : Icons.cloud_done_outlined,
            label: refreshLabel,
            color: statusColor,
          ),
          const SizedBox(height: 7),
          _OrdersStatusLabel(
            icon: Icons.schedule,
            label: intervalLabel,
            color: scheme.onSurfaceVariant,
          ),
          if (soundAvailable) ...[
            const SizedBox(height: 7),
            _OrdersStatusLabel(
              icon: soundReady
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              label: soundLabel,
              color: soundReady ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

class _OrdersStatusLabel extends StatelessWidget {
  const _OrdersStatusLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.order,
    required this.highlighted,
    required this.updating,
    required this.onChangeStatus,
    required this.onCopy,
  });

  final Order order;
  final bool highlighted;
  final bool updating;
  final VoidCallback onChangeStatus;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final customerName =
        order.businessName.isEmpty ? 'عميل B2B' : order.businessName;
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
        leading: const CircleAvatar(
          backgroundColor: AppTheme.green,
          child: Icon(Icons.receipt_long, color: Colors.white),
        ),
        title: Text(
          'طلب ${order.displayNumber}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '$customerName • ${order.items.length} منتجات • ${lyd(order.total)} • ${_date(order.createdAt)}',
        ),
        trailing: StatusChip.order(order.status),
        children: [
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(customerName),
            subtitle: Text(
              [
                if (order.contactPerson.isNotEmpty) order.contactPerson,
                if (order.contactPhone.isNotEmpty) order.contactPhone,
              ].isEmpty
                  ? 'بيانات التواصل غير متوفرة'
                  : [
                      if (order.contactPerson.isNotEmpty) order.contactPerson,
                      if (order.contactPhone.isNotEmpty) order.contactPhone,
                    ].join(' • '),
            ),
          ),
          if (order.deliveryAddress.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('عنوان التسليم'),
              subtitle: Text(order.deliveryAddress),
            ),
          _AdminOrderInvoice(order: order),
          ListTile(
            title: const Text('ملاحظة العميل'),
            subtitle: Text(
              order.customerNote.isEmpty ? 'لا توجد' : order.customerNote,
            ),
          ),
          ListTile(
            title: const Text('ملاحظة الإدارة'),
            subtitle:
                Text(order.adminNote.isEmpty ? 'لا توجد' : order.adminNote),
          ),
          if (order.statusHistory.isNotEmpty)
            ExpansionTile(
              leading: const Icon(Icons.timeline),
              title: const Text('سجل الحالات'),
              children: [
                for (final entry in order.statusHistory)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline, size: 20),
                    title: Text(
                      entry.fromStatus == null
                          ? entry.toStatus.label
                          : '${entry.fromStatus!.label} ← ${entry.toStatus.label}',
                    ),
                    subtitle: Text(
                      [
                        _dateTime(entry.changedAt),
                        if (entry.note.isNotEmpty) entry.note,
                      ].join(' • '),
                    ),
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: updating || order.allowedNextStatuses.isEmpty
                      ? null
                      : onChangeStatus,
                  icon: updating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_note),
                  label: Text(updating ? 'جارٍ التحديث...' : 'تغيير الحالة'),
                ),
                OutlinedButton.icon(
                  onPressed: updating ? null : onCopy,
                  icon: const Icon(Icons.copy),
                  label: const Text('نسخ ملخص واتساب'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOrderInvoice extends StatelessWidget {
  const _AdminOrderInvoice({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final itemCountLabel =
        order.items.length == 1 ? 'صنف واحد' : '${order.items.length} أصناف';

    return Container(
      key: ValueKey('admin-order-invoice-${order.id}'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: scheme.primary.withValues(alpha: .08),
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'تفاصيل الفاتورة',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    itemCountLabel,
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (order.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'لا توجد أصناف مسجلة في هذا الطلب.',
                textAlign: TextAlign.center,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final enlargedText =
                    MediaQuery.textScalerOf(context).scale(1) >= 1.3;
                return constraints.maxWidth >= 560 && !enlargedText
                    ? _AdminInvoiceWideTable(
                        key: ValueKey(
                          'admin-order-items-wide-${order.id}',
                        ),
                        items: order.items,
                      )
                    : _AdminInvoiceCompactList(
                        key: ValueKey(
                          'admin-order-items-compact-${order.id}',
                        ),
                        items: order.items,
                      );
              },
            ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _AdminInvoiceTotalRow(
                  label: 'الإجمالي الفرعي',
                  amount: order.subtotal,
                ),
                if (order.deliveryFee > 0)
                  _AdminInvoiceTotalRow(
                    label: 'التوصيل',
                    amount: order.deliveryFee,
                  ),
                if (order.handlingFee > 0)
                  _AdminInvoiceTotalRow(
                    label: 'المناولة',
                    amount: order.handlingFee,
                  ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _AdminInvoiceTotalRow(
                    label: 'الإجمالي المعتمد',
                    amount: order.total,
                    bold: true,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminInvoiceWideTable extends StatelessWidget {
  const _AdminInvoiceWideTable({required this.items, super.key});

  final List<OrderLine> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headerStyle = TextStyle(
      color: scheme.onSurfaceVariant,
      fontSize: 11,
      fontWeight: FontWeight.w800,
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: scheme.surfaceContainerHighest.withValues(alpha: .45),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Semantics(
                  header: true,
                  child: Text('الصنف', style: headerStyle),
                ),
              ),
              Expanded(
                flex: 2,
                child: Semantics(
                  header: true,
                  child: Text(
                    'الكمية',
                    textAlign: TextAlign.center,
                    style: headerStyle,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Semantics(
                  header: true,
                  child: Text(
                    'سعر الوحدة',
                    textAlign: TextAlign.center,
                    style: headerStyle,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Semantics(
                  header: true,
                  child: Text(
                    'الإجمالي',
                    textAlign: TextAlign.center,
                    style: headerStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var index = 0; index < items.length; index++)
          Container(
            key: ValueKey(
              'admin-invoice-line-${items[index].productId}-$index',
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              border: index == items.length - 1
                  ? null
                  : Border(
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child:
                      _AdminInvoiceProduct(item: items[index], imageSize: 48),
                ),
                Expanded(
                  flex: 2,
                  child: Semantics(
                    label: 'الكمية ${items[index].quantity}',
                    excludeSemantics: true,
                    child: Text(
                      '${items[index].quantity}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Semantics(
                    label: 'سعر الوحدة ${lyd(items[index].unitPrice)}',
                    excludeSemantics: true,
                    child: Text(
                      lyd(items[index].unitPrice),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Semantics(
                    label: 'إجمالي الصنف ${lyd(items[index].lineTotal)}',
                    excludeSemantics: true,
                    child: Text(
                      lyd(items[index].lineTotal),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AdminInvoiceCompactList extends StatelessWidget {
  const _AdminInvoiceCompactList({required this.items, super.key});

  final List<OrderLine> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var index = 0; index < items.length; index++)
          Container(
            key: ValueKey(
              'admin-invoice-line-${items[index].productId}-$index',
            ),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: index == items.length - 1
                  ? null
                  : Border(
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AdminInvoiceProduct(item: items[index], imageSize: 56),
                const SizedBox(height: 9),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        scheme.surfaceContainerHighest.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AdminInvoiceMetric(
                          label: 'الكمية',
                          value: '${items[index].quantity}',
                        ),
                      ),
                      _AdminInvoiceMetricDivider(color: scheme.outlineVariant),
                      Expanded(
                        child: _AdminInvoiceMetric(
                          label: 'سعر الوحدة',
                          value: lyd(items[index].unitPrice),
                        ),
                      ),
                      _AdminInvoiceMetricDivider(color: scheme.outlineVariant),
                      Expanded(
                        child: _AdminInvoiceMetric(
                          label: 'الإجمالي',
                          value: lyd(items[index].lineTotal),
                          bold: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AdminInvoiceProduct extends StatelessWidget {
  const _AdminInvoiceProduct({
    required this.item,
    required this.imageSize,
  });

  final OrderLine item;
  final double imageSize;

  @override
  Widget build(BuildContext context) {
    final packageLabel = item.packageLabel.trim();
    final productSku = item.productSku.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductImagePlaceholder(
          category: item.product.category,
          productId: item.productId,
          imageUrl: item.product.imageUrl,
          semanticLabel: 'صورة ${item.productName}',
          size: imageSize,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              if (packageLabel.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  packageLabel,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
              if (productSku.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  productSku,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminInvoiceMetric extends StatelessWidget {
  const _AdminInvoiceMetric({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminInvoiceMetricDivider extends StatelessWidget {
  const _AdminInvoiceMetricDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: color,
    );
  }
}

class _AdminInvoiceTotalRow extends StatelessWidget {
  const _AdminInvoiceTotalRow({
    required this.label,
    required this.amount,
    this.bold = false,
    this.padding = const EdgeInsets.symmetric(vertical: 3),
  });

  final String label;
  final double amount;
  final bool bold;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
      fontSize: bold ? 14 : 12,
    );
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 10),
          Text(lyd(amount), style: style),
        ],
      ),
    );
  }
}

class _AdminOrdersError extends StatelessWidget {
  const _AdminOrdersError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 58,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            const Text(
              'تعذر تحميل الطلبات',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text('تحقق من الاتصال والصلاحيات ثم حاول مجدداً.'),
            const SizedBox(height: 16),
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

class _StatusUpdate {
  const _StatusUpdate({required this.status, required this.note});

  final OrderStatus status;
  final String note;
}

String _date(DateTime date) => '${date.year}/${date.month}/${date.day}';

String _dateTime(DateTime date) =>
    '${_date(date)} ${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

String _shortTime(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

String _durationLabel(Duration duration) {
  if (duration.inSeconds < 60) return 'كل ${duration.inSeconds} ثانية';
  final minutes = duration.inMinutes;
  return minutes == 1 ? 'كل دقيقة' : 'كل $minutes دقائق';
}

List<Order> _deduplicateOrders(Iterable<Order> source) {
  final seen = <String>{};
  return [
    for (final order in source)
      if (seen.add(order.id)) order,
  ];
}
