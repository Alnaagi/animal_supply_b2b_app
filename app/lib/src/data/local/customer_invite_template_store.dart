import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/support/customer_invite_copy.dart';

final customerInviteTemplateStoreProvider =
    Provider<CustomerInviteTemplateStore>(
  (ref) => CustomerInviteTemplateStore(),
);

/// Device-local default WhatsApp invite wording for admin-created customers.
/// Does not change Auth, RLS, or server-generated invite tokens.
class CustomerInviteTemplateStore {
  CustomerInviteTemplateStore({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const storageKey = 'admin_customers.invite_template.v1';

  final SharedPreferences? _prefsOverride;
  final Future<SharedPreferences?> Function()? _storeLoader;
  SharedPreferences? _prefs;

  Future<SharedPreferences?> _store() async {
    if (_prefsOverride != null) return _prefsOverride;
    try {
      return _prefs ??=
          await (_storeLoader?.call() ?? SharedPreferences.getInstance());
    } catch (_) {
      return null;
    }
  }

  Future<String> load() async {
    final prefs = await _store();
    final raw = prefs?.getString(storageKey)?.trim() ?? '';
    if (raw.isEmpty) return defaultCustomerInviteTemplate;
    return raw;
  }

  Future<bool> save(String template) async {
    final trimmed = template.trim();
    if (trimmed.isEmpty) return false;
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(storageKey, trimmed);
    } catch (_) {
      return false;
    }
  }

  Future<bool> reset() => save(defaultCustomerInviteTemplate);
}
