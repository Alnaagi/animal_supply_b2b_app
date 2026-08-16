import 'cross_tab_alert_lock_stub.dart'
    if (dart.library.js_interop) 'cross_tab_alert_lock_web.dart' as platform;

/// Claims a notification id so two tabs of the same admin do not both alert.
abstract class CrossTabAlertLock {
  bool claim(String id);

  void Function()? listen(void Function(String id) onClaimed);
}

class MemoryCrossTabAlertLock implements CrossTabAlertLock {
  MemoryCrossTabAlertLock({Set<String>? claimedIds})
      : _claimedIds = claimedIds ?? <String>{};

  final Set<String> _claimedIds;

  @override
  bool claim(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return false;
    return _claimedIds.add(trimmed);
  }

  @override
  void Function()? listen(void Function(String id) onClaimed) => null;
}

CrossTabAlertLock createCrossTabAlertLock() =>
    platform.createCrossTabAlertLockImpl();
