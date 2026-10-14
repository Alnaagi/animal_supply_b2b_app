import 'package:flutter/material.dart';

import '../admin_storefront_controller.dart';
import 'storefront_design_panel.dart';
import 'storefront_page_panel.dart';
import 'storefront_sections_panel.dart';

class StorefrontSidebar extends StatelessWidget {
  const StorefrontSidebar({
    required this.state,
    required this.controller,
    this.onReset,
    super.key,
  });

  final StorefrontBuilderState state;
  final AdminStorefrontController controller;
  final VoidCallback? onReset;

  static const expandedWidth = 300.0;
  static const collapsedWidth = 56.0;

  @override
  Widget build(BuildContext context) {
    final collapsed = state.sidebarCollapsed;
    return AnimatedContainer(
      key: const Key('storefront-sidebar'),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: collapsed ? collapsedWidth : expandedWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: collapsed
          ? _CollapsedRail(onExpand: controller.toggleSidebarCollapsed)
          : _ExpandedSidebar(
              state: state,
              controller: controller,
              onReset: onReset,
            ),
    );
  }
}

class _CollapsedRail extends StatelessWidget {
  const _CollapsedRail({required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(
          tooltip: 'توسيع اللوحة',
          onPressed: onExpand,
          icon: const Icon(Icons.chevron_left),
        ),
        const Divider(height: 1),
        const Spacer(),
      ],
    );
  }
}

class _ExpandedSidebar extends StatelessWidget {
  const _ExpandedSidebar({
    required this.state,
    required this.controller,
    this.onReset,
  });

  final StorefrontBuilderState state;
  final AdminStorefrontController controller;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  key: const Key('storefront-sidebar-mode-tabs'),
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final mode in StorefrontSidebarMode.values)
                      ChoiceChip(
                        label: Text(mode.labelAr),
                        selected: state.sidebarMode == mode,
                        onSelected: (_) => controller.setSidebarMode(mode),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'طي اللوحة',
                onPressed: controller.toggleSidebarCollapsed,
                icon: const Icon(Icons.chevron_right, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: IndexedStack(
            index: state.sidebarMode.index,
            children: [
              StorefrontSectionsPanel(
                config: state.draft,
                selected: state.selectedSection,
                onSelect: controller.selectSection,
                onReorder: controller.reorderSection,
                onVisibilityChanged: controller.setSectionVisible,
              ),
              StorefrontDesignPanel(
                state: state,
                controller: controller,
                onReset: onReset,
              ),
              StorefrontPagePanel(
                state: state,
                controller: controller,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
