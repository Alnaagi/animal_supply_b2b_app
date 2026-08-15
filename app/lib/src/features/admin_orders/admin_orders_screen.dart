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
import '../../data/local/admin_orders_filter_store.dart';
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

  Set<OrderStatus> includedStatuses = AdminOrdersFilterStore.productDefault;
  Set<OrderStatus> savedIncludedStatuses =
      AdminOrdersFilterStore.productDefault;
  late bool todayOnly;
  late bool soundEnabled;
  late bool soundReady;
  final ScrollController listScrollController = ScrollController();
  final Map<String, GlobalKey> orderCardKeys = {};
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
        unawaited(_bootstrapOrders());
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
    listScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlightedOrderId = widget.highlightedOrderId;
    final soundAvailable = ref.watch(newOrderAlertSoundProvider).isAvailable;
    final compactLayout = MediaQuery.sizeOf(context).width < 600;
    return AdminShell(
      title: 'إدارة الطلبات',
      child: initialLoading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null && orders.isEmpty
              ? _AdminOrdersError(onRetry: _manualRefresh)
              : RefreshIndicator(
                  onRefresh: _manualRefresh,
                  child: ListView(
                    controller: listScrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      compactLayout ? 12 : 18,
                      14,
                      compactLayout ? 12 : 18,
                      28,
                    ),
                    children: [
                      _OrdersLiveStatus(
                        autoRefreshInterval: widget.autoRefreshInterval,
                        refreshing: refreshing,
                        lastUpdatedAt: lastUpdatedAt,
                        refreshFailed: loadError != null,
                        soundAvailable: soundAvailable,
                        soundEnabled: soundEnabled,
                        soundReady: soundReady,
                        refreshBlocked: _backgroundRefreshBlocked,
                        soundToggleBusy: soundToggleBusy,
                        onRefresh: () => unawaited(_manualRefresh()),
                        onToggleSound: () => unawaited(_toggleSound()),
                      ),
                      const SizedBox(height: 12),
                      _AdminOrdersFilterPanel(
                        todayOnly: todayOnly,
                        includedStatuses: includedStatuses,
                        orderCount: orders.length,
                        hasMore: hasMore,
                        onTodayOnlyChanged: _setTodayOnly,
                        onStatusPresetChanged: _setStatusPreset,
                        onOpenSettings: () => unawaited(_showFilterSettings()),
                      ),
                      const SizedBox(height: 14),
                      if (orders.isEmpty)
                        _AdminOrdersEmptyState(
                          hasActiveFilters: todayOnly ||
                              !AdminOrdersFilterStore.sameSet(
                                includedStatuses,
                                AdminOrdersFilterStore.allStatuses,
                              ),
                          onClearFilters: _clearFilters,
                        )
                      else
                        for (final order in orders)
                          _AdminOrderCard(
                            key: ValueKey('admin-order-card-${order.id}'),
                            cardKey: _cardKeyFor(order.id),
                            order: order,
                            highlighted: order.id == highlightedOrderId,
                            updating: updatingOrderId == order.id,
                            onExpanded: () => _scrollOrderIntoView(order.id),
                            onSelectStatus: (status, note) => unawaited(
                              _applyStatus(order, status, note: note),
                            ),
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

  void _setStatusPreset(String preset) {
    final next = switch (preset) {
      'all' => AdminOrdersFilterStore.allStatuses,
      'except_delivered' => AdminOrdersFilterStore.productDefault,
      'custom' => includedStatuses,
      _ => {
          for (final status in OrderStatus.values)
            if (status.value == preset) status,
        },
    };
    if (next.isEmpty ||
        AdminOrdersFilterStore.sameSet(next, includedStatuses)) {
      return;
    }
    setState(() => includedStatuses = next);
    unawaited(_reload(showFullLoading: true));
  }

  void _clearFilters() {
    final restored = {...savedIncludedStatuses};
    if (!todayOnly &&
        AdminOrdersFilterStore.sameSet(includedStatuses, restored)) {
      return;
    }
    setState(() {
      todayOnly = false;
      includedStatuses = restored;
    });
    unawaited(_reload(showFullLoading: true));
  }

  GlobalKey _cardKeyFor(String orderId) =>
      orderCardKeys.putIfAbsent(orderId, GlobalKey.new);

  ({OrderStatus? status, List<OrderStatus>? statuses}) get _statusQuery =>
      AdminOrdersFilterStore.queryArgs(includedStatuses);

  Future<void> _bootstrapOrders() async {
    await _reload(showFullLoading: true);
    await _restoreSavedFilterPrefs();
  }

  Future<void> _restoreSavedFilterPrefs() async {
    final saved = await ref.read(adminOrdersFilterStoreProvider).load();
    if (!mounted) return;
    final alreadyApplied = AdminOrdersFilterStore.sameSet(
          saved,
          includedStatuses,
        ) &&
        AdminOrdersFilterStore.sameSet(saved, savedIncludedStatuses);
    setState(() {
      savedIncludedStatuses = saved;
      includedStatuses = saved;
    });
    if (alreadyApplied) return;
    await _reload(showFullLoading: true);
    final highlightedId = widget.highlightedOrderId?.trim() ?? '';
    if (highlightedId.isNotEmpty) {
      _scrollOrderIntoView(highlightedId);
    }
  }

  void _scrollOrderIntoView(String orderId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureOrderVisible(orderId));
    });
  }

  Future<void> _ensureOrderVisible(String orderId) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    final context = _cardKeyFor(orderId).currentContext;
    if (context == null || !context.mounted) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _showFilterSettings() async {
    final draft = {...includedStatuses};
    final saved = await showDialog<Set<OrderStatus>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canSave = draft.isNotEmpty;
            return AlertDialog(
              title: const Text('إعدادات التصفية'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'اختر الحالات التي تظهر افتراضياً عند فتح إدارة الطلبات. يتم حفظ الاختيار على هذا الجهاز فقط.',
                        style: TextStyle(fontSize: 13, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      for (final status in OrderStatus.values)
                        CheckboxListTile(
                          key: ValueKey(
                            'admin-orders-filter-pref-${status.value}',
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: draft.contains(status),
                          title: Text(status.label),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (selected) {
                            setDialogState(() {
                              if (selected == true) {
                                draft.add(status);
                              } else {
                                draft.remove(status);
                              }
                            });
                          },
                        ),
                      if (!canSave)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'اختر حالة واحدة على الأقل.',
                            style: TextStyle(
                              color: AppTheme.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      draft
                        ..clear()
                        ..addAll(AdminOrdersFilterStore.productDefault);
                    });
                  },
                  child: const Text('إعادة الافتراضي'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: canSave
                      ? () => Navigator.pop(dialogContext, {...draft})
                      : null,
                  child: const Text('حفظ الإعدادات'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved == null || !mounted) return;
    final persisted = await ref.read(adminOrdersFilterStoreProvider).save(saved);
    if (!mounted) return;
    setState(() {
      savedIncludedStatuses = saved;
      includedStatuses = saved;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          persisted
              ? 'تم حفظ إعدادات التصفية على هذا الجهاز.'
              : 'تعذر حفظ الإعدادات على الجهاز، لكن سيتم استخدامها في هذه الجلسة.',
        ),
      ),
    );
    await _reload(showFullLoading: true);
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
        status: _statusQuery.status,
        statuses: _statusQuery.statuses,
        createdFrom: range.from,
        createdUntil: range.until,
        pageSize: _pageSize,
      );
      var loaded = page.orders;
      final highlightedId = widget.highlightedOrderId?.trim() ?? '';
      if (highlightedId.isNotEmpty &&
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
            status: _statusQuery.status,
            statuses: _statusQuery.statuses,
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
    final filteredView = todayOnly ||
        !AdminOrdersFilterStore.sameSet(
          includedStatuses,
          savedIncludedStatuses,
        );
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

  Future<void> _applyStatus(
    Order order,
    OrderStatus status, {
    String note = '',
  }) async {
    if (!order.allowedNextStatuses.contains(status)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            order.status == OrderStatus.delivered
                ? 'الطلب مسلّم ولا توجد حالة تالية.'
                : order.status == OrderStatus.cancelled
                    ? 'الطلب ملغي ولا يمكن تغيير حالته.'
                    : 'لا يمكن نقل الطلب مباشرةً إلى هذه الحالة.',
          ),
        ),
      );
      return;
    }

    setState(() => updatingOrderId = order.id);
    try {
      await ref.read(ordersRepositoryProvider).transitionOrderStatus(
            order.id,
            status,
            adminNote: note,
          );
      if (AppConfig.isDemoMode) {
        ref.read(notificationsRepositoryProvider).addDemoOrderStatus(
              orderId: order.id,
              statusLabel: status.label,
            );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحديث الطلب إلى: ${status.label}'),
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
    required this.refreshBlocked,
    required this.soundToggleBusy,
    required this.onRefresh,
    required this.onToggleSound,
  });

  final Duration autoRefreshInterval;
  final bool refreshing;
  final DateTime? lastUpdatedAt;
  final bool refreshFailed;
  final bool soundAvailable;
  final bool soundEnabled;
  final bool soundReady;
  final bool refreshBlocked;
  final bool soundToggleBusy;
  final VoidCallback onRefresh;
  final VoidCallback onToggleSound;

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

    return Semantics(
      container: true,
      label: '$refreshLabel، $intervalLabel، $soundLabel',
      child: Container(
        key: const ValueKey('admin-orders-live-status'),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              statusColor.withValues(alpha: .11),
              statusColor.withValues(alpha: .045),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: statusColor.withValues(alpha: .20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .14),
                    shape: BoxShape.circle,
                  ),
                  child: refreshing
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: statusColor,
                          ),
                        )
                      : Icon(
                          refreshFailed
                              ? Icons.sync_problem_outlined
                              : Icons.cloud_done_outlined,
                          color: statusColor,
                          size: 21,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        refreshFailed
                            ? 'توجد مشكلة في آخر تحديث'
                            : 'متابعة الطلبات مباشرة',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        refreshLabel,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (soundAvailable) ...[
                  const SizedBox(width: 5),
                  IconButton.filledTonal(
                    key: const ValueKey(
                      'toggle-admin-orders-sound-button',
                    ),
                    onPressed: soundToggleBusy ? null : onToggleSound,
                    tooltip: !soundEnabled
                        ? 'تشغيل صوت الطلبات الجديدة'
                        : soundReady
                            ? 'إيقاف صوت الطلبات الجديدة'
                            : 'اضغط لتفعيل صوت الطلبات الجديدة',
                    icon: soundToggleBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            !soundEnabled
                                ? Icons.volume_off_outlined
                                : soundReady
                                    ? Icons.volume_up
                                    : Icons.volume_up_outlined,
                          ),
                  ),
                ],
                const SizedBox(width: 3),
                IconButton.filled(
                  key: const ValueKey('refresh-admin-orders-button'),
                  onPressed: refreshBlocked ? null : onRefresh,
                  tooltip: 'تحديث الطلبات الآن',
                  icon: refreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _OrdersStatusPill(
                  icon: Icons.schedule,
                  label: intervalLabel,
                ),
                if (soundAvailable)
                  _OrdersStatusPill(
                    icon: soundReady
                        ? Icons.volume_up_outlined
                        : Icons.volume_off_outlined,
                    label: soundLabel,
                    highlighted: soundReady,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersStatusPill extends StatelessWidget {
  const _OrdersStatusPill({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlighted ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOrdersFilterPanel extends StatelessWidget {
  const _AdminOrdersFilterPanel({
    required this.todayOnly,
    required this.includedStatuses,
    required this.orderCount,
    required this.hasMore,
    required this.onTodayOnlyChanged,
    required this.onStatusPresetChanged,
    required this.onOpenSettings,
  });

  final bool todayOnly;
  final Set<OrderStatus> includedStatuses;
  final int orderCount;
  final bool hasMore;
  final ValueChanged<bool> onTodayOnlyChanged;
  final ValueChanged<String> onStatusPresetChanged;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateControl = _AdminOrdersDateFilter(
      todayOnly: todayOnly,
      onChanged: onTodayOnlyChanged,
    );
    final statusControl = _AdminOrdersStatusFilter(
      includedStatuses: includedStatuses,
      onPresetChanged: onStatusPresetChanged,
      onOpenSettings: onOpenSettings,
    );

    return Container(
      key: const ValueKey('admin-orders-filter-panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.tune,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تصفية الطلبات',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'اختر الفترة والحالات للوصول أسرع',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                key: const ValueKey('admin-orders-result-summary'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  hasMore ? '$orderCount+ طلب' : '$orderCount طلب',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final enlargedText =
                  MediaQuery.textScalerOf(context).scale(1) >= 1.3;
              if (constraints.maxWidth >= 520 && !enlargedText) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: dateControl),
                    const SizedBox(width: 12),
                    Expanded(child: statusControl),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dateControl,
                  const SizedBox(height: 12),
                  statusControl,
                ],
              );
            },
          ),
          if (hasMore) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.history,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'توجد طلبات أقدم ويمكن تحميلها من نهاية القائمة.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminOrdersDateFilter extends StatelessWidget {
  const _AdminOrdersDateFilter({
    required this.todayOnly,
    required this.onChanged,
  });

  final bool todayOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الفترة',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          key: const ValueKey('admin-orders-date-filter'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.calendar_view_month_outlined, size: 17),
              label: Text(
                'كل الأيام',
                key: ValueKey('admin-orders-date-all'),
              ),
            ),
            ButtonSegment<bool>(
              value: true,
              icon: Icon(Icons.today_outlined, size: 17),
              label: Text(
                'اليوم',
                key: ValueKey('admin-orders-date-today'),
              ),
            ),
          ],
          selected: {todayOnly},
          onSelectionChanged: (selection) => onChanged(selection.single),
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

class _AdminOrdersStatusFilter extends StatelessWidget {
  const _AdminOrdersStatusFilter({
    required this.includedStatuses,
    required this.onPresetChanged,
    required this.onOpenSettings,
  });

  final Set<OrderStatus> includedStatuses;
  final ValueChanged<String> onPresetChanged;
  final VoidCallback onOpenSettings;

  String get _value {
    if (AdminOrdersFilterStore.sameSet(
      includedStatuses,
      AdminOrdersFilterStore.allStatuses,
    )) {
      return 'all';
    }
    if (AdminOrdersFilterStore.sameSet(
      includedStatuses,
      AdminOrdersFilterStore.productDefault,
    )) {
      return 'except_delivered';
    }
    if (includedStatuses.length == 1) return includedStatuses.single.value;
    return 'custom';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = _value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'الحالة',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              key: const ValueKey('admin-orders-filter-settings'),
              tooltip: 'إعدادات التصفية',
              visualDensity: VisualDensity.compact,
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor:
                      scheme.surfaceContainerHighest.withValues(alpha: .38),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const ValueKey('admin-orders-status-filter'),
                    value: value,
                    isDense: true,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(14),
                    icon: const Icon(Icons.keyboard_arrow_down),
                    items: [
                      const DropdownMenuItem<String>(
                        key: ValueKey('admin-orders-status-except-delivered'),
                        value: 'except_delivered',
                        child: Text('كل الحالات ما عدا المُسلَّم'),
                      ),
                      const DropdownMenuItem<String>(
                        key: ValueKey('admin-orders-status-all-option'),
                        value: 'all',
                        child: Text('كل الحالات'),
                      ),
                      if (value == 'custom')
                        const DropdownMenuItem<String>(
                          value: 'custom',
                          child: Text('حسب إعداداتك'),
                        ),
                      for (final status in OrderStatus.values)
                        DropdownMenuItem<String>(
                          key: ValueKey(
                            'admin-orders-status-${status.value}',
                          ),
                          value: status.value,
                          child: Text(status.label),
                        ),
                    ],
                    onChanged: (selected) {
                      if (selected != null) onPresetChanged(selected);
                    },
                  ),
                ),
              ),
            ),
            if (value != 'except_delivered') ...[
              const SizedBox(width: 6),
              IconButton.filledTonal(
                key: const ValueKey('admin-orders-status-all'),
                onPressed: () => onPresetChanged('except_delivered'),
                tooltip: 'عرض كل الحالات ما عدا المُسلَّم',
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _AdminOrdersEmptyState extends StatelessWidget {
  const _AdminOrdersEmptyState({
    required this.hasActiveFilters,
    required this.onClearFilters,
  });

  final bool hasActiveFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('admin-orders-empty-state'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .09),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasActiveFilters
                  ? Icons.filter_alt_off_outlined
                  : Icons.receipt_long_outlined,
              color: scheme.primary,
              size: 29,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasActiveFilters
                ? 'لا توجد طلبات بهذه التصفية'
                : 'لا توجد طلبات بعد',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            hasActiveFilters
                ? 'جرّب فترة أو حالة مختلفة لعرض نتائج أخرى.'
                : 'ستظهر الطلبات الجديدة هنا فور وصولها.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if (hasActiveFilters) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey('admin-orders-clear-filters'),
              onPressed: onClearFilters,
              icon: const Icon(Icons.restart_alt),
              label: const Text('إعادة التصفية الافتراضية'),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.order,
    required this.highlighted,
    required this.updating,
    required this.onExpanded,
    required this.onSelectStatus,
    required this.onCopy,
    this.cardKey,
    super.key,
  });

  final Order order;
  final bool highlighted;
  final bool updating;
  final VoidCallback onExpanded;
  final void Function(OrderStatus status, String note) onSelectStatus;
  final VoidCallback onCopy;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final customerName =
        order.businessName.isEmpty ? 'عميل B2B' : order.businessName;
    final scheme = Theme.of(context).colorScheme;
    final hasNotes = order.customerNote.trim().isNotEmpty ||
        order.adminNote.trim().isNotEmpty;
    return Card(
      key: cardKey,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: highlighted ? 3 : 1,
      color: highlighted
          ? scheme.primaryContainer.withValues(alpha: .18)
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: highlighted
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: ExpansionTile(
        key: PageStorageKey<String>('admin-order-expansion-${order.id}'),
        initiallyExpanded: highlighted,
        maintainState: true,
        onExpansionChanged: (expanded) {
          if (expanded) onExpanded();
        },
        tilePadding: const EdgeInsetsDirectional.fromSTEB(14, 10, 10, 10),
        childrenPadding: EdgeInsets.zero,
        iconColor: scheme.primary,
        collapsedIconColor: scheme.onSurfaceVariant,
        shape: const Border(),
        collapsedShape: const Border(),
        title: _AdminOrderSummary(
          key: ValueKey('admin-order-summary-${order.id}'),
          order: order,
          customerName: customerName,
        ),
        children: [
          Divider(height: 1, color: scheme.outlineVariant),
          Container(
            key: ValueKey('admin-order-details-${order.id}'),
            color: scheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AdminOrderCustomerDelivery(
                  order: order,
                  customerName: customerName,
                ),
                _AdminOrderInvoice(order: order),
                if (hasNotes) _AdminOrderNotes(order: order),
                if (order.statusHistory.isNotEmpty)
                  _AdminOrderHistory(order: order),
                _AdminOrderActions(
                  order: order,
                  updating: updating,
                  onSelectStatus: onSelectStatus,
                  onCopy: onCopy,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOrderSummary extends StatelessWidget {
  const _AdminOrderSummary({
    required this.order,
    required this.customerName,
    super.key,
  });

  final Order order;
  final String customerName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: scheme.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'طلب ${order.displayNumber}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              StatusChip.order(order.status),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _AdminOrderFact(
                icon: Icons.payments_outlined,
                label: lyd(order.total),
                emphasized: true,
              ),
              _AdminOrderFact(
                icon: Icons.inventory_2_outlined,
                label: '${order.items.length} أصناف',
              ),
              _AdminOrderFact(
                icon: Icons.calendar_today_outlined,
                label: _date(order.createdAt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminOrderFact extends StatelessWidget {
  const _AdminOrderFact({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = emphasized ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: emphasized
            ? scheme.primary.withValues(alpha: .08)
            : scheme.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOrderCustomerDelivery extends StatelessWidget {
  const _AdminOrderCustomerDelivery({
    required this.order,
    required this.customerName,
  });

  final Order order;
  final String customerName;

  @override
  Widget build(BuildContext context) {
    final customerDetails = <Widget>[
      _AdminOrderDetailLine(
        label: 'المنشأة',
        value: customerName,
      ),
      if (order.contactPerson.trim().isNotEmpty)
        _AdminOrderDetailLine(
          label: 'مسؤول التواصل',
          value: order.contactPerson.trim(),
        ),
      if (order.contactPhone.trim().isNotEmpty)
        _AdminOrderDetailLine(
          label: 'رقم الهاتف',
          value: order.contactPhone.trim(),
          ltr: true,
        ),
      if (order.contactPerson.trim().isEmpty &&
          order.contactPhone.trim().isEmpty)
        const _AdminOrderMissingDetail(
          message: 'بيانات التواصل غير متوفرة في هذا الطلب.',
        ),
    ];
    final deliveryDetails = <Widget>[
      if (order.deliveryAddress.trim().isNotEmpty)
        _AdminOrderDetailLine(
          label: 'عنوان التسليم',
          value: order.deliveryAddress.trim(),
        ),
      if (order.deliveryNote.trim().isNotEmpty)
        _AdminOrderDetailLine(
          label: 'تعليمات التسليم',
          value: order.deliveryNote.trim(),
        ),
      if (order.deliveryAddress.trim().isEmpty &&
          order.deliveryNote.trim().isEmpty)
        const _AdminOrderMissingDetail(
          message: 'لم يُسجل عنوان أو تعليمات تسليم.',
        ),
    ];

    return Container(
      key: ValueKey('admin-order-customer-delivery-${order.id}'),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: _AdminOrderSection(
        icon: Icons.local_shipping_outlined,
        title: 'العميل والتسليم',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final enlargedText =
                MediaQuery.textScalerOf(context).scale(1) >= 1.3;
            final customer = _AdminOrderDetailGroup(
              icon: Icons.storefront_outlined,
              title: 'بيانات العميل',
              children: customerDetails,
            );
            final delivery = _AdminOrderDetailGroup(
              icon: Icons.location_on_outlined,
              title: 'بيانات التسليم',
              children: deliveryDetails,
            );
            if (constraints.maxWidth >= 520 && !enlargedText) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: customer),
                  const SizedBox(width: 10),
                  Expanded(child: delivery),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                customer,
                const SizedBox(height: 9),
                delivery,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminOrderSection extends StatelessWidget {
  const _AdminOrderSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: scheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          child,
        ],
      ),
    );
  }
}

class _AdminOrderDetailGroup extends StatelessWidget {
  const _AdminOrderDetailGroup({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) Divider(height: 13, color: scheme.outlineVariant),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _AdminOrderDetailLine extends StatelessWidget {
  const _AdminOrderDetailLine({
    required this.label,
    required this.value,
    this.ltr = false,
  });

  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        if (ltr)
          SelectableText(
            value,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          )
        else
          Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
      ],
    );
  }
}

class _AdminOrderMissingDetail extends StatelessWidget {
  const _AdminOrderMissingDetail({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 15,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminOrderNotes extends StatelessWidget {
  const _AdminOrderNotes({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final notes = <Widget>[
      if (order.customerNote.trim().isNotEmpty)
        _AdminOrderNoteCard(
          icon: Icons.chat_bubble_outline,
          title: 'ملاحظة العميل',
          note: order.customerNote.trim(),
          color: AppTheme.orange,
        ),
      if (order.adminNote.trim().isNotEmpty)
        _AdminOrderNoteCard(
          icon: Icons.admin_panel_settings_outlined,
          title: 'ملاحظة الإدارة',
          note: order.adminNote.trim(),
          color: Theme.of(context).colorScheme.primary,
        ),
    ];

    return Container(
      key: ValueKey('admin-order-notes-${order.id}'),
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: _AdminOrderSection(
        icon: Icons.notes_outlined,
        title: 'الملاحظات',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final enlargedText =
                MediaQuery.textScalerOf(context).scale(1) >= 1.3;
            if (notes.length > 1 &&
                constraints.maxWidth >= 520 &&
                !enlargedText) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: notes[0]),
                  const SizedBox(width: 10),
                  Expanded(child: notes[1]),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < notes.length; index++) ...[
                  if (index > 0) const SizedBox(height: 9),
                  notes[index],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminOrderNoteCard extends StatelessWidget {
  const _AdminOrderNoteCard({
    required this.icon,
    required this.title,
    required this.note,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .075),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(note, style: const TextStyle(fontSize: 11.5, height: 1.45)),
        ],
      ),
    );
  }
}

class _AdminOrderHistory extends StatelessWidget {
  const _AdminOrderHistory({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final latest = order.statusHistory.last;
    return Container(
      key: ValueKey('admin-order-history-${order.id}'),
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ExpansionTile(
        key: ValueKey('admin-order-history-toggle-${order.id}'),
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.timeline, size: 18, color: scheme.primary),
        ),
        title: Text(
          'سجل الحالة (${order.statusHistory.length})',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
        ),
        subtitle: Text(
          'آخر تحديث ${_dateTime(latest.changedAt)}',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 10.5,
          ),
        ),
        children: [
          Container(
            key: ValueKey('admin-order-history-body-${order.id}'),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                Divider(height: 1, color: scheme.outlineVariant),
                const SizedBox(height: 8),
                for (var index = 0; index < order.statusHistory.length; index++)
                  _AdminOrderHistoryEntry(
                    entry: order.statusHistory[index],
                    last: index == order.statusHistory.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOrderHistoryEntry extends StatelessWidget {
  const _AdminOrderHistoryEntry({
    required this.entry,
    required this.last,
  });

  final OrderStatusHistoryEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final transition = entry.fromStatus == null
        ? 'بدأ الطلب بحالة ${entry.toStatus.label}'
        : 'من ${entry.fromStatus!.label} إلى ${entry.toStatus.label}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: scheme.primary.withValues(alpha: .22),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    transition,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dateTime(entry.changedAt),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                  if (entry.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.note.trim(),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOrderActions extends StatefulWidget {
  const _AdminOrderActions({
    required this.order,
    required this.updating,
    required this.onSelectStatus,
    required this.onCopy,
  });

  final Order order;
  final bool updating;
  final void Function(OrderStatus status, String note) onSelectStatus;
  final VoidCallback onCopy;

  @override
  State<_AdminOrderActions> createState() => _AdminOrderActionsState();
}

class _AdminOrderActionsState extends State<_AdminOrderActions> {
  final TextEditingController note = TextEditingController();
  OrderStatus? pendingConfirm;

  @override
  void didUpdateWidget(covariant _AdminOrderActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.id != widget.order.id ||
        oldWidget.order.status != widget.order.status) {
      pendingConfirm = null;
      note.clear();
    }
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  bool _needsConfirm(OrderStatus status) =>
      status == OrderStatus.cancelled || status == OrderStatus.delivered;

  void _onStatusPressed(OrderStatus status) {
    if (widget.updating) return;
    if (_needsConfirm(status)) {
      setState(() => pendingConfirm = status);
      return;
    }
    widget.onSelectStatus(status, note.text.trim());
  }

  void _confirmPending() {
    final status = pendingConfirm;
    if (status == null || widget.updating) return;
    widget.onSelectStatus(status, note.text.trim());
    setState(() => pendingConfirm = null);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final scheme = Theme.of(context).colorScheme;
    final nextStatuses = order.allowedNextStatuses;
    final copyButton = SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        key: ValueKey('admin-order-copy-summary-${order.id}'),
        onPressed: widget.updating ? null : widget.onCopy,
        icon: const Icon(Icons.copy),
        label: const Text('نسخ ملخص واتساب'),
      ),
    );
    final statusActions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'الحالة الحالية',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            StatusChip.order(order.status),
          ],
        ),
        const SizedBox(height: 8),
        if (nextStatuses.isEmpty)
          Row(
            children: [
              Icon(
                order.status == OrderStatus.delivered
                    ? Icons.task_alt
                    : Icons.block_outlined,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  order.status == OrderStatus.delivered
                      ? 'اكتملت دورة هذا الطلب.'
                      : 'لا يمكن تغيير حالة هذا الطلب.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          )
        else ...[
          Text(
            widget.updating ? 'جارٍ التحديث...' : 'الخطوة التالية',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            key: ValueKey('admin-order-change-status-${order.id}'),
            constraints: const BoxConstraints(minHeight: 48),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in nextStatuses)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: status == OrderStatus.cancelled
                        ? OutlinedButton(
                            key: ValueKey(
                              'admin-order-next-status-${order.id}-${status.value}',
                            ),
                            onPressed: widget.updating
                                ? null
                                : () => _onStatusPressed(status),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error),
                            ),
                            child: Text(status.label),
                          )
                        : FilledButton(
                            key: ValueKey(
                              'admin-order-next-status-${order.id}-${status.value}',
                            ),
                            onPressed: widget.updating
                                ? null
                                : () => _onStatusPressed(status),
                            child: Text(status.label),
                          ),
                  ),
              ],
            ),
          ),
          if (pendingConfirm != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    pendingConfirm == OrderStatus.cancelled
                        ? 'إلغاء الطلب نهائي ولا يمكن التراجع عنه.'
                        : 'تسليم الطلب نهائي ولا يمكن التراجع عنه.',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          key: ValueKey(
                            'admin-order-confirm-status-${order.id}',
                          ),
                          onPressed: widget.updating ? null : _confirmPending,
                          child: Text(
                            pendingConfirm == OrderStatus.cancelled
                                ? 'تأكيد الإلغاء'
                                : 'تأكيد التسليم',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: widget.updating
                            ? null
                            : () => setState(() => pendingConfirm = null),
                        child: const Text('تراجع'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: note,
            enabled: !widget.updating,
            maxLines: 2,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'ملاحظة الإدارة (اختيارية)',
            ),
          ),
        ],
      ],
    );

    return Container(
      key: ValueKey('admin-order-actions-${order.id}'),
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: .14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statusActions,
          const SizedBox(height: 9),
          copyButton,
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
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
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
