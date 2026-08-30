import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/notifications_repository.dart';
import '../../notifications/notification_center_sheet.dart';
import '../admin_storefront_controller.dart';

class StorefrontToolbar extends ConsumerWidget {
  const StorefrontToolbar({
    required this.state,
    required this.controller,
    required this.onReset,
    required this.onPublish,
    super.key,
  });

  final StorefrontBuilderState state;
  final AdminStorefrontController controller;
  final VoidCallback onReset;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread =
        ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    final showMenu = MediaQuery.sizeOf(context).width < 900;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Prefer available toolbar width (nav rail shrinks content) over raw viewport.
        final compact = constraints.maxWidth < 1100 ||
            MediaQuery.sizeOf(context).width < 1200;
        return Material(
          key: const Key('storefront-toolbar'),
          color: Colors.white,
          elevation: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: compact
                  ? _CompactToolbar(
                      state: state,
                      controller: controller,
                      onReset: onReset,
                      onPublish: onPublish,
                      showMenu: showMenu,
                      unread: unread,
                    )
                  : _WideToolbar(
                      state: state,
                      controller: controller,
                      onReset: onReset,
                      onPublish: onPublish,
                      showMenu: showMenu,
                      unread: unread,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _StorefrontNotificationsButton extends ConsumerWidget {
  const _StorefrontNotificationsButton({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      key: const Key('storefront-notifications-button'),
      tooltip: 'الإشعارات',
      onPressed: () => showNotificationCenter(context, ref),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class _WideToolbar extends StatelessWidget {
  const _WideToolbar({
    required this.state,
    required this.controller,
    required this.onReset,
    required this.onPublish,
    required this.showMenu,
    required this.unread,
  });

  final StorefrontBuilderState state;
  final AdminStorefrontController controller;
  final VoidCallback onReset;
  final VoidCallback onPublish;
  final bool showMenu;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (showMenu)
          IconButton(
            key: const Key('storefront-toolbar-menu-button'),
            tooltip: 'فتح قائمة الإدارة',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu),
          ),
        Icon(Icons.palette_outlined, color: scheme.primary, size: 22),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تصميم المتجر',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              _DraftStatusChip(state: state),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _StorefrontNotificationsButton(unread: unread),
        const SizedBox(width: 4),
        _UndoRedoGroup(controller: controller),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: _PrimaryActions(
                state: state,
                onPublish: onPublish,
                onPreviewPublished: () =>
                    controller.togglePreviewPublished(true),
                onReset: onReset,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactToolbar extends StatelessWidget {
  const _CompactToolbar({
    required this.state,
    required this.controller,
    required this.onReset,
    required this.onPublish,
    required this.showMenu,
    required this.unread,
  });

  final StorefrontBuilderState state;
  final AdminStorefrontController controller;
  final VoidCallback onReset;
  final VoidCallback onPublish;
  final bool showMenu;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (showMenu)
              IconButton(
                key: const Key('storefront-toolbar-menu-button'),
                tooltip: 'فتح قائمة الإدارة',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu),
              ),
            const Expanded(
              child: Text(
                'تصميم المتجر',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
            _StorefrontNotificationsButton(unread: unread),
            _UndoRedoGroup(controller: controller),
          ],
        ),
        const SizedBox(height: 8),
        _DraftStatusChip(state: state),
        const SizedBox(height: 8),
        _PrimaryActions(
          state: state,
          onPublish: onPublish,
          onPreviewPublished: () => controller.togglePreviewPublished(true),
          onReset: onReset,
          compact: true,
        ),
      ],
    );
  }
}

class _DraftStatusChip extends StatelessWidget {
  const _DraftStatusChip({required this.state});

  final StorefrontBuilderState state;

  @override
  Widget build(BuildContext context) {
    final saving = state.saving ||
        state.syncStatus == StorefrontDraftSyncStatus.saving;
    final error = state.syncStatus == StorefrontDraftSyncStatus.error;
    final pending = state.hasUnsavedChanges ||
        state.syncStatus == StorefrontDraftSyncStatus.pending;
    final Color color;
    if (error) {
      color = Colors.red.shade700;
    } else if (saving || pending) {
      color = Colors.orange;
    } else if (state.hasUnpublishedChanges) {
      color = Colors.blue.shade700;
    } else {
      color = Theme.of(context).colorScheme.primary;
    }
    return Container(
      key: const Key('storefront-draft-status-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (saving)
            SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Icon(
              error
                  ? Icons.error_outline
                  : pending
                      ? Icons.edit_note
                      : state.hasUnpublishedChanges
                          ? Icons.cloud_upload_outlined
                          : Icons.check_circle_outline,
              size: 14,
              color: color,
            ),
          const SizedBox(width: 6),
          Text(
            state.draftStatusLabelAr,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _UndoRedoGroup extends StatelessWidget {
  const _UndoRedoGroup({required this.controller});

  final AdminStorefrontController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('storefront-undo-button'),
            tooltip: 'تراجع',
            onPressed: controller.canUndo ? controller.undo : null,
            icon: const Icon(Icons.undo),
          ),
          Container(width: 1, height: 24, color: Colors.grey.shade300),
          IconButton(
            key: const Key('storefront-redo-button'),
            tooltip: 'إعادة',
            onPressed: controller.canRedo ? controller.redo : null,
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({
    required this.state,
    required this.onPublish,
    required this.onPreviewPublished,
    required this.onReset,
    this.compact = false,
  });

  final StorefrontBuilderState state;
  final VoidCallback onPublish;
  final VoidCallback onPreviewPublished;
  final VoidCallback onReset;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      OutlinedButton.icon(
        key: const Key('storefront-reset-button'),
        onPressed: state.saving || state.publishing ? null : onReset,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red.shade700,
          side: BorderSide(color: Colors.red.shade400),
        ),
        icon: const Icon(Icons.restart_alt, size: 18),
        label: const Text('إعادة ضبط'),
      ),
      OutlinedButton.icon(
        onPressed: onPreviewPublished,
        icon: const Icon(Icons.visibility_outlined, size: 18),
        label: const Text('معاينة المنشور'),
      ),
      FilledButton.icon(
        onPressed: state.publishing ? null : onPublish,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
        icon: state.publishing
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.publish, size: 18),
        label: const Text('نشر التغييرات'),
      ),
    ];

    if (compact) {
      return Wrap(spacing: 8, runSpacing: 8, children: children);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        children[i],
      ],
    ]);
  }
}
