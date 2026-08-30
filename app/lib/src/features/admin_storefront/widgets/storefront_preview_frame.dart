import 'package:flutter/material.dart';

import '../admin_storefront_controller.dart';

class StorefrontPreviewFrame extends StatelessWidget {
  const StorefrontPreviewFrame({
    required this.device,
    required this.child,
    this.compact = false,
    super.key,
  });

  final StorefrontPreviewDevice device;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return switch (device) {
      StorefrontPreviewDevice.phone => _PhonePreviewFrame(
          compact: compact,
          child: child,
        ),
      StorefrontPreviewDevice.desktop => _DesktopPreviewFrame(
          compact: compact,
          child: child,
        ),
    };
  }
}

/// Edge-to-edge phone portrait frame (~390) matching live compact customer shell.
class _PhonePreviewFrame extends StatelessWidget {
  const _PhonePreviewFrame({
    required this.compact,
    required this.child,
  });

  final bool compact;
  final Widget child;

  static const _phoneMaxWidth = 430.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 390.0;
        final maxH =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 844.0;
        final previewWidth = maxW.clamp(280.0, _phoneMaxWidth);

        // Fill the canvas height so the beige host does not show a dead zone
        // below the phone frame.
        return SizedBox(
          width: maxW,
          height: maxH,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: previewWidth,
              height: maxH,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(compact ? 12 : 28),
                  border:
                      Border.all(color: Colors.black.withValues(alpha: .06)),
                  boxShadow: compact
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(compact ? 12 : 28),
                  child: KeyedSubtree(
                    key: Key(
                      compact
                          ? 'storefront-preview-compact-phone-portrait'
                          : 'storefront-preview-phone-portrait',
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: Size(previewWidth, maxH),
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Wide desktop frame: real desktop constraints (not a phone column scaled up).
class _DesktopPreviewFrame extends StatelessWidget {
  const _DesktopPreviewFrame({
    required this.compact,
    required this.child,
  });

  final bool compact;
  final Widget child;

  static const _desktopWidth = 1200.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW =
            constraints.maxWidth.isFinite ? constraints.maxWidth : _desktopWidth;
        final maxH =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 800.0;

        // Always expose desktop logical width so AppBreakpoints / CustomerShell
        // match live desktop (rail + desktop app bar), even when the admin
        // panel is narrower and we scale to fit.
        final scale = (maxW / _desktopWidth).clamp(0.01, 1.0);
        final logicalHeight = maxH / scale;

        return SizedBox(
          key: Key(
            compact
                ? 'storefront-preview-compact-desktop'
                : 'storefront-preview-desktop',
          ),
          width: maxW,
          height: maxH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(compact ? 12 : 16),
              border: Border.all(color: Colors.black.withValues(alpha: .08)),
              boxShadow: compact
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 12 : 16),
              child: FittedBox(
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: _desktopWidth,
                  height: logicalHeight,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(_desktopWidth, logicalHeight),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
