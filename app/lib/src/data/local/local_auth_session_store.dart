import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../repositories/demo_data.dart';

/// Persists the labelled demo identity and last in-app route across reloads.
///
/// Production auth tokens stay in the Supabase session store. This class never
/// stores passwords, refresh tokens, or a service-role key.
class LocalAuthSessionStore {
  LocalAuthSessionStore({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const userKey = 'auth.local_demo_session.v1';
  static const routeKey = 'auth.last_route.v1';

  static final LocalAuthSessionStore instance = LocalAuthSessionStore();

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

  Future<AppUser?> readDemoUser() async {
    final prefs = await _store();
    final raw = prefs?.getString(userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final id = decoded['id']?.toString();
      return demoUserById(id);
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveDemoUser(AppUser user) async {
    if (!user.isDemo) return false;
    final canonical = demoUserById(user.id);
    if (canonical == null) return false;
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(userKey, jsonEncode({'id': canonical.id}));
    } catch (_) {
      return false;
    }
  }

  Future<void> clearDemoUser() async {
    final prefs = await _store();
    try {
      await prefs?.remove(userKey);
    } catch (_) {}
  }

  Future<String?> readLastRoute() async {
    final prefs = await _store();
    final route = prefs?.getString(routeKey)?.trim();
    if (route == null || route.isEmpty || route.length > 1000) return null;
    return route;
  }

  Future<bool> saveLastRoute(String route) async {
    final trimmed = route.trim();
    if (trimmed.isEmpty || trimmed.length > 1000) return false;
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(routeKey, trimmed);
    } catch (_) {
      return false;
    }
  }

  Future<void> clearLastRoute() async {
    final prefs = await _store();
    try {
      await prefs?.remove(routeKey);
    } catch (_) {}
  }

  Future<void> clear() async {
    await clearDemoUser();
    await clearLastRoute();
  }
}

AppUser? demoUserById(String? id) {
  return switch (id) {
    'admin-1' => demoAdmin.copyWith(isDemo: true),
    'staff-1' => demoStaff.copyWith(isDemo: true),
    'customer-user-1' => demoCustomer.copyWith(
        accountStatus: 'active',
        isDemo: true,
      ),
    _ => null,
  };
}
