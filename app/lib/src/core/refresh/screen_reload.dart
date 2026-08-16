import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped after create/edit/delete/status saves so kept-alive screens
/// (customer IndexedStack) rerun the same reload as their refresh button.
final screenReloadTickProvider = StateProvider<int>((ref) => 0);

void listenForScreenReload(
  WidgetRef ref,
  Future<void> Function() reload,
) {
  ref.listen<int>(screenReloadTickProvider, (previous, next) {
    if (previous != next) unawaited(reload());
  });
}

void requestScreenReload(WidgetRef ref) {
  ref.read(screenReloadTickProvider.notifier).state++;
}

/// Waits for the closed dialog route to settle, then runs [reload].
Future<void> reloadAfterMutation(
  State state,
  Future<void> Function() reload,
) async {
  await Future<void>.delayed(Duration.zero);
  if (!state.mounted) return;
  await reload();
}
