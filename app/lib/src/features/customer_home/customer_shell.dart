import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/config/app_runtime_mode.dart';
import '../../core/config/shop_branding.dart';
import '../../core/notifications/browser_notification_permission_banner.dart';
import '../../core/notifications/cart_reminder_poller.dart';
import '../../core/notifications/in_app_notification_poller.dart';
import '../../core/notifications/push_notifications.dart';
import '../../core/support/whatsapp_support.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/network_status.dart';
import '../../core/widgets/shop_brand_logo.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/sync/outbox_retry_coordinator.dart';
import '../../data/sync/sync_outbox.dart';
import '../auth/auth_controller.dart';
import '../cart/cart_controller.dart';
import '../storefront/storefront_theme_scope.dart';
import 'cart_attention_nudge_icon.dart';

class CustomerShell extends ConsumerStatefulWidget {
  const CustomerShell({
    required this.shell,
    required this.currentLocation,
    super.key,
  });

  final StatefulNavigationShell shell;
  final String currentLocation;

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  static const _cartScrollInactivityDelay = Duration(seconds: 22);
  static const _cartNudgeDuration = Duration(milliseconds: 2000);
  static const _cartCooldown = Duration(seconds: 35);

  Timer? _cartNudgeTimer;
  Timer? _cartNudgeResetTimer;
  Timer? _cartCooldownTimer;
  bool _isCartNudging = false;
  bool _isInCooldown = false;

  void _goToBranch(int index) {
    widget.shell.goBranch(
      index,
      initialLocation: index == widget.shell.currentIndex,
    );
  }

  void _onUserScrolled() {
    final cartCount = ref.read(
      cartControllerProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
    );
    final isOnCartScreen = widget.shell.currentIndex == 2 ||
        widget.currentLocation == '/cart' ||
        widget.currentLocation == '/checkout';

    if (cartCount <= 0 || isOnCartScreen) {
      _cancelNudgeTimers();
      if (_isCartNudging && mounted) {
        setState(() => _isCartNudging = false);
      }
      return;
    }

    if (_isCartNudging || _isInCooldown) {
      return;
    }

    _cartNudgeTimer ??= Timer(_cartScrollInactivityDelay, _triggerCartNudge);
  }

  void _triggerCartNudge() {
    _cartNudgeTimer?.cancel();
    _cartNudgeTimer = null;
    if (!mounted) return;

    final cartCount = ref.read(
      cartControllerProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
    );
    final isOnCartScreen = widget.shell.currentIndex == 2 ||
        widget.currentLocation == '/cart' ||
        widget.currentLocation == '/checkout';

    if (cartCount <= 0 || isOnCartScreen) {
      return;
    }

    setState(() {
      _isCartNudging = true;
      _isInCooldown = true;
    });

    _cartNudgeResetTimer?.cancel();
    _cartNudgeResetTimer = Timer(_cartNudgeDuration, () {
      if (mounted) {
        setState(() => _isCartNudging = false);
      }
    });

    _cartCooldownTimer?.cancel();
    _cartCooldownTimer = Timer(_cartCooldown, () {
      if (mounted) {
        _isInCooldown = false;
      }
    });
  }

  void _cancelNudgeTimers() {
    _cartNudgeTimer?.cancel();
    _cartNudgeTimer = null;
    _cartNudgeResetTimer?.cancel();
    _cartNudgeResetTimer = null;
    _cartCooldownTimer?.cancel();
    _cartCooldownTimer = null;
    _isInCooldown = false;
  }

  @override
  void didUpdateWidget(covariant CustomerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isOnCartScreen = widget.shell.currentIndex == 2 ||
        widget.currentLocation == '/cart' ||
        widget.currentLocation == '/checkout';
    if (isOnCartScreen) {
      _cancelNudgeTimers();
      if (_isCartNudging) {
        _isCartNudging = false;
      }
    }
  }

  @override
  void dispose() {
    _cancelNudgeTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep connectivity-triggered place-order outbox flush alive for customers.
    ref.watch(outboxRetryCoordinatorProvider);
    final user = ref.watch(authControllerProvider).user;
    final settings = ref.watch(appSettingsProvider).asData?.value;
    final branding = ref.watch(shopBrandingProvider);
    final shopName = branding.shopName;
    final supportPhone = settings?.supportWhatsapp.trim().isNotEmpty == true
        ? settings!.supportWhatsapp
        : AppConfig.supportWhatsapp;
    ref.listen<OutboxSyncNotice?>(outboxSyncNoticeProvider, (previous, next) {
      if (next == null ||
          next.ownerProfileId != user?.id ||
          identical(previous, next)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إرسال الطلب المحفوظ ${next.orderNumber} واعتماده بنجاح.',
          ),
        ),
      );
    });
    ref.listen<int>(
      cartControllerProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
      (previous, next) {
        if (next <= 0) {
          _cancelNudgeTimers();
          if (_isCartNudging && mounted) {
            setState(() => _isCartNudging = false);
          }
        } else if (next > (previous ?? 0)) {
          _triggerCartNudge();
        }
      },
    );
    final cartCount = ref.watch(
      cartControllerProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
    );
    final queuedOrderCount = user == null
        ? 0
        : ref
                .watch(customerOrderOutboxProvider(user.id))
                .asData
                ?.value
                .totalCount ??
            0;
    final supportReady = WhatsAppSupport.isConfiguredFor(supportPhone);
    final demoMode = AppConfig.isDemoMode ||
        ref.watch(appRuntimeModeProvider) ||
        user?.isDemo == true;

    Future<void> openSupport() async {
      final opened = await WhatsAppSupport.openMessage(
        'مرحباً، أحتاج مساعدة في تطبيق $shopName.',
        phone: supportPhone,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح واتساب حالياً')),
        );
      }
    }

    void signOut() {
      ref
          .read(pushNotificationsCoordinatorProvider)
          .signOut(ref.read(authControllerProvider.notifier));
    }

    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);

    return PublishedStorefrontTheme(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = AppBreakpoints.isCompact(constraints.maxWidth);
          final extendedRail = AppBreakpoints.isExpanded(constraints.maxWidth);
          final routeProvidesAppBar =
              _routeProvidesCompactAppBar(widget.currentLocation);

          final content = _CustomerShellContent(
            demoMode: demoMode,
            onUserScrolled: _onUserScrolled,
            child: widget.shell,
          );
          return Scaffold(
            key: const Key('customer-shell-scaffold'),
            appBar: compact && routeProvidesAppBar
                ? null
                : _CustomerTopBar(
                    compact: compact,
                    shopName: shopName,
                    logoUrl: branding.logoUrl,
                    supportReady: supportReady,
                    onSupport: openSupport,
                    onLogout: signOut,
                  ),
            body: compact
                ? content
                : Row(
                    children: [
                      _CustomerNavigationRail(
                        currentIndex: widget.shell.currentIndex,
                        extended: extendedRail,
                        cartCount: cartCount,
                        queuedOrderCount: queuedOrderCount,
                        isCartNudging: _isCartNudging,
                        reduceMotion: reduceMotion,
                        onDestinationSelected: _goToBranch,
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _customerContentMaxWidth,
                            ),
                            child: SizedBox(
                              key: const Key('customer-centered-content'),
                              width: double.infinity,
                              height: double.infinity,
                              child: content,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
            bottomNavigationBar: compact
                ? _CustomerBottomNavigation(
                    currentIndex: widget.shell.currentIndex,
                    cartCount: cartCount,
                    queuedOrderCount: queuedOrderCount,
                    isCartNudging: _isCartNudging,
                    reduceMotion: reduceMotion,
                    onDestinationSelected: _goToBranch,
                  )
                : null,
          );
        },
      ),
    );
  }
}

const _customerContentMaxWidth = 1320.0;

/// Admin storefront preview chrome that mirrors live [CustomerShell] layout
/// (app bar, bottom nav / rail) without executing cart, orders, or logout.
class CustomerPreviewShell extends ConsumerWidget {
  const CustomerPreviewShell({
    required this.child,
    this.selectedIndex = 0,
    super.key,
  });

  final Widget child;
  final int selectedIndex;

  static const previewOnlyMessage =
      'وضع المعاينة — لا يمكن تنفيذ هذا الإجراء من هنا.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(shopBrandingProvider);
    final shopName = branding.shopName;
    final settings = ref.watch(appSettingsProvider).asData?.value;
    final supportPhone = settings?.supportWhatsapp.trim().isNotEmpty == true
        ? settings!.supportWhatsapp
        : AppConfig.supportWhatsapp;
    final supportReady = WhatsAppSupport.isConfiguredFor(supportPhone);

    Future<void> openSupport() async {
      final opened = await WhatsAppSupport.openMessage(
        'مرحباً، أحتاج مساعدة في تطبيق $shopName.',
        phone: supportPhone,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح واتساب حالياً')),
        );
      }
    }

    void previewOnly() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(previewOnlyMessage)),
      );
    }

    void onDestinationSelected(int index) {
      if (index == selectedIndex) return;
      previewOnly();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = AppBreakpoints.isCompact(constraints.maxWidth);
        final extendedRail = AppBreakpoints.isExpanded(constraints.maxWidth);

        return Scaffold(
          key: const Key('customer-preview-shell-scaffold'),
          appBar: _CustomerTopBar(
            compact: compact,
            shopName: shopName,
            logoUrl: branding.logoUrl,
            supportReady: supportReady,
            onSupport: openSupport,
            onLogout: previewOnly,
          ),
          body: compact
              ? child
              : Row(
                  children: [
                    _CustomerNavigationRail(
                      currentIndex: selectedIndex,
                      extended: extendedRail,
                      cartCount: 0,
                      queuedOrderCount: 0,
                      onDestinationSelected: onDestinationSelected,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _customerContentMaxWidth,
                          ),
                          child: SizedBox(
                            key: const Key('customer-preview-centered-content'),
                            width: double.infinity,
                            height: double.infinity,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: compact
              ? _CustomerBottomNavigation(
                  currentIndex: selectedIndex,
                  cartCount: 0,
                  queuedOrderCount: 0,
                  onDestinationSelected: onDestinationSelected,
                )
              : null,
        );
      },
    );
  }
}

bool _routeProvidesCompactAppBar(String location) =>
    location == '/checkout' ||
    location == '/offers' ||
    location == '/support' ||
    location.startsWith('/product/');

class _CustomerTopBar extends StatefulWidget implements PreferredSizeWidget {
  const _CustomerTopBar({
    required this.compact,
    required this.shopName,
    required this.logoUrl,
    required this.supportReady,
    required this.onSupport,
    required this.onLogout,
  });

  final bool compact;
  final String shopName;
  final String? logoUrl;
  final bool supportReady;
  final VoidCallback onSupport;
  final VoidCallback onLogout;

  @override
  Size get preferredSize => Size.fromHeight(compact ? kToolbarHeight : 72);

  @override
  State<_CustomerTopBar> createState() => _CustomerTopBarState();
}

class _CustomerTopBarState extends State<_CustomerTopBar> {
  static const _supportRevealDelay = Duration(seconds: 4);
  static const _supportVisibleDuration = Duration(seconds: 5);

  Timer? _supportRevealTimer;
  Timer? _supportCollapseTimer;
  bool _supportExpanded = false;
  bool _supportRevealScheduled = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
      if (reduceMotion) {
        _cancelSupportTimers();
        _supportExpanded = false;
      }
    }
    _scheduleSupportReveal();
  }

  @override
  void didUpdateWidget(covariant _CustomerTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compact != widget.compact ||
        oldWidget.supportReady != widget.supportReady) {
      _cancelSupportTimers();
      _supportExpanded = false;
      _supportRevealScheduled = false;
      _scheduleSupportReveal();
    }
  }

  void _scheduleSupportReveal() {
    if (!widget.compact ||
        !widget.supportReady ||
        _reduceMotion ||
        _supportRevealScheduled) {
      return;
    }
    _supportRevealScheduled = true;
    _supportRevealTimer = Timer(_supportRevealDelay, () {
      if (!mounted) return;
      setState(() => _supportExpanded = true);
      _supportCollapseTimer = Timer(_supportVisibleDuration, () {
        if (!mounted) return;
        setState(() => _supportExpanded = false);
      });
    });
  }

  void _cancelSupportTimers() {
    _supportRevealTimer?.cancel();
    _supportRevealTimer = null;
    _supportCollapseTimer?.cancel();
    _supportCollapseTimer = null;
  }

  @override
  void dispose() {
    _cancelSupportTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.compact) {
      return _buildCompactTopBar(context);
    }

    return AppBar(
      key: const Key('customer-desktop-app-bar'),
      automaticallyImplyLeading: false,
      centerTitle: false,
      toolbarHeight: widget.preferredSize.height,
      titleSpacing: AppSpacing.lg,
      title: _ShopIdentity(
        compact: false,
        shopName: widget.shopName,
        logoUrl: widget.logoUrl,
      ),
      actions: [
        if (widget.supportReady)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
            child: OutlinedButton.icon(
              key: const Key('customer-desktop-support-action'),
              onPressed: widget.onSupport,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.whatsapp,
                side: BorderSide(
                  color: AppTheme.whatsapp.withValues(alpha: .42),
                ),
                backgroundColor: AppTheme.whatsapp.withValues(alpha: .08),
              ),
              icon: const FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 19,
              ),
              label: const Text('مساعدة عبر واتساب'),
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.xs,
            end: AppSpacing.lg,
          ),
          child: TextButton.icon(
            key: const Key('customer-desktop-logout-action'),
            onPressed: widget.onLogout,
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            icon: const Icon(Icons.logout_rounded, size: 20),
            label: const Text('تسجيل الخروج'),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactTopBar(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width;
    final nudgeExpandedWidth =
        (availableWidth - 120).clamp(152.0, 186.0).toDouble();
    final animationDuration =
        _reduceMotion ? Duration.zero : AppMotion.emphasized;

    // AppBar leading is the visual right in RTL. Animating its actual layout
    // width keeps the nudge inside the toolbar instead of placing a full-screen
    // floating hit target over the page.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _supportExpanded ? 1 : 0),
      duration: animationDuration,
      curve: AppMotion.standardCurve,
      builder: (context, progress, _) {
        final leadingWidth = widget.supportReady
            ? 56 + ((nudgeExpandedWidth + 8) - 56) * progress
            : 0.0;
        final titleMaxWidth =
            (availableWidth - leadingWidth - 56).clamp(0.0, double.infinity);
        return AppBar(
          key: const Key('customer-mobile-app-bar'),
          automaticallyImplyLeading: false,
          centerTitle: true,
          toolbarHeight: widget.preferredSize.height,
          titleSpacing: NavigationToolbar.kMiddleSpacing,
          leadingWidth: widget.supportReady ? leadingWidth : null,
          leading: widget.supportReady
              ? Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: KeyedSubtree(
                    key: const Key('customer-mobile-support-action'),
                    child: CustomerSupportNudge(
                      expanded: _supportExpanded,
                      expandProgress: progress,
                      expandedWidth: nudgeExpandedWidth,
                      reduceMotion: _reduceMotion,
                      onTap: widget.onSupport,
                    ),
                  ),
                )
              : null,
          title: IgnorePointer(
            ignoring: progress > .7,
            child: Opacity(
              key: const Key('customer-shop-identity-opacity'),
              opacity: 1 - progress,
              child: ClipRect(
                child: SizedBox(
                  width: titleMaxWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: _ShopIdentity(
                      compact: true,
                      shopName: widget.shopName,
                      logoUrl: widget.logoUrl,
                    ),
                  ),
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
              key: const Key('customer-mobile-logout-action'),
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'تسجيل الخروج',
            ),
          ],
        );
      },
    );
  }
}

class _ShopIdentity extends StatelessWidget {
  const _ShopIdentity({
    required this.compact,
    required this.shopName,
    required this.logoUrl,
  });

  final bool compact;
  final String shopName;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShopBrandLogo(
          logoUrl: logoUrl,
          size: compact ? 36 : 42,
          backgroundColor: scheme.primary,
          fallbackIconColor: scheme.onPrimary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: compact
              ? Text(
                  shopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'متجر توريد الجملة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CustomerShellContent extends StatelessWidget {
  const _CustomerShellContent({
    required this.demoMode,
    required this.child,
    this.onUserScrolled,
  });

  final bool demoMode;
  final Widget child;
  final VoidCallback? onUserScrolled;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification ||
            notification is UserScrollNotification ||
            notification is ScrollStartNotification) {
          onUserScrolled?.call();
        }
        return false;
      },
      child: Column(
        children: [
          if (demoMode) const DemoModeNotice(),
          const NetworkStatusHeader(),
          const BrowserNotificationPermissionBanner(),
          const InAppNotificationPoller(),
          const CartReminderPoller(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _CustomerBottomNavigation extends StatelessWidget {
  const _CustomerBottomNavigation({
    required this.currentIndex,
    required this.cartCount,
    required this.queuedOrderCount,
    required this.onDestinationSelected,
    this.isCartNudging = false,
    this.reduceMotion = false,
  });

  final int currentIndex;
  final int cartCount;
  final int queuedOrderCount;
  final bool isCartNudging;
  final bool reduceMotion;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor =
        theme.navigationBarTheme.backgroundColor ?? Colors.white;
    final borderColor =
        theme.dividerTheme.color ?? theme.colorScheme.outlineVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: barColor,
        border: Border(
          top: BorderSide(
            color: borderColor,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          key: const Key('customer-bottom-navigation'),
          selectedIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: _bottomDestinations(
            cartCount: cartCount,
            queuedOrderCount: queuedOrderCount,
            isCartNudging: isCartNudging,
            reduceMotion: reduceMotion,
          ),
        ),
      ),
    );
  }
}

class _CustomerNavigationRail extends StatelessWidget {
  const _CustomerNavigationRail({
    required this.currentIndex,
    required this.extended,
    required this.cartCount,
    required this.queuedOrderCount,
    required this.onDestinationSelected,
    this.isCartNudging = false,
    this.reduceMotion = false,
  });

  final int currentIndex;
  final bool extended;
  final int cartCount;
  final int queuedOrderCount;
  final bool isCartNudging;
  final bool reduceMotion;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      key: const Key('customer-navigation-rail'),
      extended: extended,
      minExtendedWidth: 224,
      selectedIndex: currentIndex,
      groupAlignment: -.84,
      labelType:
          extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      onDestinationSelected: onDestinationSelected,
      destinations: _railDestinations(
        cartCount: cartCount,
        queuedOrderCount: queuedOrderCount,
        isCartNudging: isCartNudging,
        reduceMotion: reduceMotion,
      ),
    );
  }
}

List<NavigationDestination> _bottomDestinations({
  required int cartCount,
  required int queuedOrderCount,
  bool isCartNudging = false,
  bool reduceMotion = false,
}) {
  return [
    const NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'الرئيسية',
    ),
    const NavigationDestination(
      icon: Icon(Icons.storefront_outlined),
      selectedIcon: Icon(Icons.storefront_rounded),
      label: 'المنتجات',
    ),
    NavigationDestination(
      icon: CartAttentionNudgeIcon(
        count: cartCount,
        icon: Icons.shopping_cart_outlined,
        isNudging: isCartNudging,
        reduceMotion: reduceMotion,
      ),
      selectedIcon: CartAttentionNudgeIcon(
        count: cartCount,
        icon: Icons.shopping_cart_rounded,
        isNudging: isCartNudging,
        reduceMotion: reduceMotion,
      ),
      label: 'السلة',
    ),
    NavigationDestination(
      icon: _NavigationBadgeIcon(
        count: queuedOrderCount,
        icon: Icons.receipt_long_outlined,
      ),
      selectedIcon: _NavigationBadgeIcon(
        count: queuedOrderCount,
        icon: Icons.receipt_long_rounded,
      ),
      label: 'الطلبات',
    ),
    const NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'الحساب',
    ),
  ];
}

List<NavigationRailDestination> _railDestinations({
  required int cartCount,
  required int queuedOrderCount,
  bool isCartNudging = false,
  bool reduceMotion = false,
}) {
  return [
    const NavigationRailDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: Text('الرئيسية'),
    ),
    const NavigationRailDestination(
      icon: Icon(Icons.storefront_outlined),
      selectedIcon: Icon(Icons.storefront_rounded),
      label: Text('المنتجات'),
    ),
    NavigationRailDestination(
      icon: CartAttentionNudgeIcon(
        count: cartCount,
        icon: Icons.shopping_cart_outlined,
        isNudging: isCartNudging,
        reduceMotion: reduceMotion,
      ),
      selectedIcon: CartAttentionNudgeIcon(
        count: cartCount,
        icon: Icons.shopping_cart_rounded,
        isNudging: isCartNudging,
        reduceMotion: reduceMotion,
      ),
      label: const Text('السلة'),
    ),
    NavigationRailDestination(
      icon: _NavigationBadgeIcon(
        count: queuedOrderCount,
        icon: Icons.receipt_long_outlined,
      ),
      selectedIcon: _NavigationBadgeIcon(
        count: queuedOrderCount,
        icon: Icons.receipt_long_rounded,
      ),
      label: const Text('الطلبات'),
    ),
    const NavigationRailDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: Text('الحساب'),
    ),
  ];
}

class _NavigationBadgeIcon extends StatelessWidget {
  const _NavigationBadgeIcon({
    required this.count,
    required this.icon,
  });

  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: Icon(icon),
    );
  }
}

/// Compact WhatsApp help chip used in isolated UX tests.
/// Prefer the shell app-bar action for live customer surfaces — do not mount
/// this as a Scaffold FAB (loose Align hit targets steal scroll/taps).
class CustomerSupportNudge extends StatefulWidget {
  const CustomerSupportNudge({
    required this.expanded,
    required this.onTap,
    this.expandProgress = 1,
    this.expandedWidth = 186,
    this.reduceMotion = false,
    super.key,
  });

  final bool expanded;
  final double expandProgress;
  final VoidCallback onTap;
  final double expandedWidth;
  final bool reduceMotion;

  @override
  State<CustomerSupportNudge> createState() => _CustomerSupportNudgeState();
}

class _CustomerSupportNudgeState extends State<CustomerSupportNudge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _updatePulse();
  }

  @override
  void didUpdateWidget(covariant CustomerSupportNudge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded ||
        oldWidget.reduceMotion != widget.reduceMotion) {
      _updatePulse();
    }
  }

  void _updatePulse() {
    if (widget.reduceMotion || widget.expanded) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _buildWhatsAppIcon() {
    const icon = FaIcon(
      FontAwesomeIcons.whatsapp,
      color: AppTheme.whatsapp,
      size: 22,
    );
    if (widget.reduceMotion || widget.expanded) {
      return icon;
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulse.value);
        return Opacity(
          opacity: 0.84 + (0.16 * t),
          child: Transform.scale(
            scale: 1 + (0.05 * t),
            child: child,
          ),
        );
      },
      child: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final expanded = widget.expanded;
    final revealProgress = expanded ? widget.expandProgress.clamp(0.0, 1.0) : 0.0;
    final frameWidth = expanded
        ? 48 + ((widget.expandedWidth - 48) * revealProgress)
        : 48.0;
    return Semantics(
      key: const Key('customer-support-nudge-semantics'),
      button: true,
      label: expanded
          ? 'تحتاج مساعدة؟ تواصل معنا عبر واتساب'
          : 'الدعم عبر واتساب',
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'الدعم عبر واتساب',
          child: Material(
            color: revealProgress > 0.2
                ? AppTheme.whatsapp.withValues(alpha: .08)
                : Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('customer-support-nudge'),
              onTap: widget.onTap,
              splashColor: AppTheme.whatsapp.withValues(alpha: .12),
              highlightColor: AppTheme.whatsapp.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: Container(
                key: const Key('customer-support-nudge-frame'),
                height: 48,
                width: frameWidth,
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
                alignment: expanded ? null : Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildWhatsAppIcon(),
                    AnimatedContainer(
                      duration: widget.reduceMotion
                          ? Duration.zero
                          : AppMotion.standard,
                      curve: AppMotion.standardCurve,
                      width: revealProgress > 0.2 ? AppSpacing.xs : 0,
                    ),
                    Expanded(
                      child: ClipRect(
                        child: AnimatedSlide(
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : AppMotion.emphasized,
                          curve: AppMotion.standardCurve,
                          offset: revealProgress > 0.35
                              ? Offset.zero
                              : const Offset(.18, 0),
                          child: AnimatedOpacity(
                            duration: widget.reduceMotion
                                ? Duration.zero
                                : AppMotion.standard,
                            curve: AppMotion.standardCurve,
                            opacity: revealProgress > 0.45 ? 1 : 0,
                            child: const Text(
                              'تحتاج مساعدة؟ اضغط هنا',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.whatsapp,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DemoModeNotice extends StatelessWidget {
  const DemoModeNotice({super.key});

  static const message =
      'وضع تجريبي — البيانات والأسعار والطلبات للعرض فقط وغير حقيقية.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message,
      child: ExcludeSemantics(
        child: Container(
          key: const Key('customer-demo-mode-notice'),
          width: double.infinity,
          color: Colors.blueGrey.shade800,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.science_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
