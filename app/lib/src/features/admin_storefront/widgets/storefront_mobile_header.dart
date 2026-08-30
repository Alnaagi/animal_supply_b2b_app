import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/notifications_repository.dart';
import '../../notifications/notification_center_sheet.dart';
import '../admin_storefront_controller.dart';

/// Compact two-row header for mobile storefront builder (<650px).
class StorefrontMobileHeader extends ConsumerWidget {
  const StorefrontMobileHeader({
    required this.state,
    required this.controller,
    required this.onPublish,
    required this.onReset,
    required this.onPreviewPublished,
    super.key,
  });

  final StorefrontBuilderState state;
  final AdminStorefrontController controller;
  final VoidCallback onPublish;
  final VoidCallback onReset;
  final VoidCallback onPreviewPublished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final saving = state.saving ||
        state.syncStatus == StorefrontDraftSyncStatus.saving;
    final error = state.syncStatus == StorefrontDraftSyncStatus.error;
    final pending = state.hasUnsavedChanges ||
        state.syncStatus == StorefrontDraftSyncStatus.pending;
    final unread =
        ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    final Color statusColor;
    if (error) {
      statusColor = Colors.red.shade700;
    } else if (saving || pending) {
      statusColor = Colors.orange;
    } else if (state.hasUnpublishedChanges) {
      statusColor = Colors.blue.shade700;
    } else {
      statusColor = scheme.primary;
    }

    return Material(
      key: const Key('storefront-mobile-header'),
      color: Colors.white,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'فتح قائمة الإدارة',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu),
                      visualDensity: VisualDensity.compact,
                    ),
                    Icon(Icons.palette_outlined,
                        color: scheme.primary, size: 20),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'تصميم المتجر',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('storefront-notifications-button'),
                      tooltip: 'الإشعارات',
                      onPressed: () => showNotificationCenter(context, ref),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Badge(
                        isLabelVisible: unread > 0,
                        label: Text(unread > 99 ? '99+' : '$unread'),
                        child: const Icon(Icons.notifications_outlined),
                      ),
                    ),
                    TextButton(
                      key: const Key('storefront-mobile-reset'),
                      onPressed:
                          state.saving || state.publishing ? null : onReset,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('إعادة ضبط'),
                    ),
                    PopupMenuButton<String>(
                      key: const Key('storefront-mobile-overflow'),
                      tooltip: 'المزيد',
                      padding: EdgeInsets.zero,
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'preview_published',
                          child: Text('معاينة المنشور'),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'preview_published') {
                          onPreviewPublished();
                        }
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          key: const Key('storefront-mobile-status'),
                          state.draftStatusLabelAr,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _UndoRedoGroup(controller: controller),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('storefront-mobile-publish'),
                        onPressed: state.publishing ? null : onPublish,
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        child: state.publishing
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('نشر'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('storefront-undo-button'),
            tooltip: 'تراجع',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            onPressed: controller.canUndo ? controller.undo : null,
            icon: const Icon(Icons.undo, size: 20),
          ),
          Container(width: 1, height: 20, color: Colors.grey.shade300),
          IconButton(
            key: const Key('storefront-redo-button'),
            tooltip: 'إعادة',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            onPressed: controller.canRedo ? controller.redo : null,
            icon: const Icon(Icons.redo, size: 20),
          ),
        ],
      ),
    );
  }
}
