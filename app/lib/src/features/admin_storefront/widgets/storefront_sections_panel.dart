import 'package:flutter/material.dart';

import '../../../data/models/storefront_config.dart';

class StorefrontSectionsPanel extends StatelessWidget {
  const StorefrontSectionsPanel({
    required this.config,
    required this.selected,
    required this.onSelect,
    required this.onReorder,
    required this.onVisibilityChanged,
    this.compact = false,
    super.key,
  });

  final StorefrontConfig config;
  final StorefrontSectionType? selected;
  final ValueChanged<StorefrontSectionType> onSelect;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(StorefrontSectionType type, bool visible)
      onVisibilityChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'ترتيب الأقسام',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            key: const Key('storefront-sections-list'),
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
            itemCount: config.sections.length,
            onReorder: onReorder,
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final t = Curves.easeInOut.transform(animation.value);
                  return Material(
                    elevation: 4 * t,
                    borderRadius: BorderRadius.circular(14),
                    child: child,
                  );
                },
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final section = config.sections[index];
              final isSelected = selected == section.type;
              return _SectionRow(
                key: ValueKey(section.type.key),
                index: index,
                section: section,
                isSelected: isSelected,
                compact: compact,
                onSelect: () => onSelect(section.type),
                onVisibilityChanged: (visible) {
                  if (!visible && _isCoreSection(section.type)) {
                    _confirmHide(context, section.type, visible);
                    return;
                  }
                  onVisibilityChanged(section.type, visible);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isCoreSection(StorefrontSectionType type) {
    return type == StorefrontSectionType.header ||
        type == StorefrontSectionType.categories;
  }

  Future<void> _confirmHide(
    BuildContext context,
    StorefrontSectionType type,
    bool visible,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إخفاء قسم أساسي'),
        content: Text(
          'إخفاء "${type.labelAr}" قد يؤثر على تجربة العملاء. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إخفاء'),
          ),
        ],
      ),
    );
    if (ok == true) onVisibilityChanged(type, visible);
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required super.key,
    required this.index,
    required this.section,
    required this.isSelected,
    required this.onSelect,
    required this.onVisibilityChanged,
    this.compact = false,
  });

  final int index;
  final StorefrontSectionConfig section;
  final bool isSelected;
  final VoidCallback onSelect;
  final ValueChanged<bool> onVisibilityChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Long-press reorder only — no drag_handle / drag_indicator graphic.
    // (Default ReorderableListView handles are disabled; those are the
    // two parallel lines that sat next to the visibility eye.)
    return ReorderableDelayedDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: isSelected
              ? scheme.primary.withValues(alpha: .12)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onSelect,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: compact ? 14 : 10,
              ),
              child: Row(
                children: [
                  Icon(
                    _iconFor(section.type),
                    color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.type.labelAr,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.w900 : FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          section.visible ? 'ظاهر' : 'مخفي',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: section.visible ? 'إخفاء' : 'إظهار',
                    onPressed: () => onVisibilityChanged(!section.visible),
                    icon: Icon(
                      section.visible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: section.visible
                          ? scheme.primary
                          : Colors.grey.shade500,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(StorefrontSectionType type) {
    switch (type) {
      case StorefrontSectionType.header:
        return Icons.home_outlined;
      case StorefrontSectionType.banner:
        return Icons.view_carousel_outlined;
      case StorefrontSectionType.categories:
        return Icons.category_outlined;
      case StorefrontSectionType.featuredProducts:
        return Icons.star_outline;
      case StorefrontSectionType.offers:
        return Icons.local_offer_outlined;
      case StorefrontSectionType.bestSelling:
        return Icons.trending_up;
      case StorefrontSectionType.latestProducts:
        return Icons.new_releases_outlined;
      case StorefrontSectionType.recentOrder:
        return Icons.replay_outlined;
    }
  }
}
