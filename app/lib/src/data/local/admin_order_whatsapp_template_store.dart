import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/support/order_whatsapp_copy.dart';
import '../models/order.dart';

final adminOrderWhatsappTemplateStoreProvider =
    Provider<AdminOrderWhatsappTemplateStore>(
  (ref) => AdminOrderWhatsappTemplateStore(),
);

/// Device-local WhatsApp order-message template and per-order overrides.
///
/// Persistence stays on this device. It does not change RLS, Auth, or
/// server-generated invoices.
class AdminOrderWhatsappTemplateStore {
  AdminOrderWhatsappTemplateStore({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const templateStorageKey = 'admin_orders.whatsapp_template.v1';
  static const overridesStorageKey = 'admin_orders.whatsapp_overrides.v1';

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

  Future<String> loadTemplate() async {
    final prefs = await _store();
    final raw = prefs?.getString(templateStorageKey)?.trim() ?? '';
    if (raw.isEmpty) return defaultOrderWhatsappTemplate;
    return raw;
  }

  Future<bool> saveTemplate(String template) async {
    final trimmed = template.trim();
    if (trimmed.isEmpty) return false;
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(templateStorageKey, trimmed);
    } catch (_) {
      return false;
    }
  }

  Future<bool> resetTemplate() => saveTemplate(defaultOrderWhatsappTemplate);

  Future<Map<String, String>> loadOverrides() async {
    final prefs = await _store();
    final raw = prefs?.getString(overridesStorageKey);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final parsed = <String, String>{};
      for (final entry in decoded.entries) {
        final text = entry.value?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        parsed[entry.key.toString()] = text;
      }
      return parsed;
    } catch (_) {
      return {};
    }
  }

  Future<String?> loadOverride(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return null;
    final overrides = await loadOverrides();
    final text = overrides[id]?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  Future<bool> saveOverride(String orderId, String message) async {
    final id = orderId.trim();
    final trimmed = message.trim();
    if (id.isEmpty || trimmed.isEmpty) return false;
    final prefs = await _store();
    if (prefs == null) return false;
    final overrides = await loadOverrides();
    overrides[id] = trimmed;
    return _writeOverrides(prefs, overrides);
  }

  Future<bool> clearOverride(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return false;
    final prefs = await _store();
    if (prefs == null) return false;
    final overrides = await loadOverrides();
    if (!overrides.containsKey(id)) return true;
    overrides.remove(id);
    return _writeOverrides(prefs, overrides);
  }

  Future<bool> _writeOverrides(
    SharedPreferences prefs,
    Map<String, String> overrides,
  ) async {
    try {
      if (overrides.isEmpty) {
        await prefs.remove(overridesStorageKey);
        return true;
      }
      return await prefs.setString(overridesStorageKey, jsonEncode(overrides));
    } catch (_) {
      return false;
    }
  }

  Future<String> resolve({
    required Order order,
    required String fallbackBusinessName,
    String shopName = '',
    String invoiceLink = '',
  }) async {
    final template = await loadTemplate();
    final override = await loadOverride(order.id);
    return resolveOrderWhatsappMessage(
      order: order,
      fallbackBusinessName: fallbackBusinessName,
      shopName: shopName,
      invoiceLink: invoiceLink,
      template: template,
      overrideText: override,
    );
  }
}
