import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool connectivityItemsAreOnline(List<ConnectivityResult> items) {
  return items.any((item) => item != ConnectivityResult.none);
}

final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  try {
    yield connectivityItemsAreOnline(await connectivity.checkConnectivity());
  } catch (_) {
    yield true;
  }
  yield* connectivity.onConnectivityChanged.map(connectivityItemsAreOnline);
});

final networkRetryTickProvider = StateProvider<int>((ref) => 0);

class RemoteActivityNotifier extends StateNotifier<int> {
  RemoteActivityNotifier() : super(0);

  void begin() {
    state++;
  }

  void end() {
    if (state > 0) state--;
  }
}

final remoteActivityProvider =
    StateNotifierProvider<RemoteActivityNotifier, int>(
  (ref) => RemoteActivityNotifier(),
);

Future<T> trackRemoteActivity<T>(
  WidgetRef ref,
  Future<T> future,
) async {
  ref.read(remoteActivityProvider.notifier).begin();
  try {
    return await future;
  } finally {
    ref.read(remoteActivityProvider.notifier).end();
  }
}

bool isOnlineFromConnectivity(AsyncValue<bool> async) {
  return async.asData?.value ?? true;
}
