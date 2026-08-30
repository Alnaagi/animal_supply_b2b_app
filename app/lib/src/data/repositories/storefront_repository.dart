import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/concurrency/stale_write.dart';
import '../../core/config/app_config.dart';
import '../models/storefront_config.dart';
import '../remote/supabase_clients.dart';

final storefrontRepositoryProvider = Provider<StorefrontRepository>(
  (ref) => StorefrontRepository(),
);

final publishedStorefrontConfigProvider = FutureProvider<StorefrontConfig>(
  (ref) => ref.watch(storefrontRepositoryProvider).loadPublished(),
);

class StorefrontRepository {
  StorefrontRepository({
    StorefrontConfig? demoDraft,
    StorefrontConfig? demoPublished,
    DateTime? demoUpdatedAt,
  })  : _demoDraft = demoDraft ?? StorefrontDefaults.bundled,
        _demoPublished = demoPublished ?? StorefrontDefaults.bundled,
        _demoUpdatedAt = demoUpdatedAt ?? DateTime.utc(2026, 1, 1);

  StorefrontConfig _demoDraft;
  StorefrontConfig _demoPublished;
  DateTime _demoUpdatedAt;
  StorefrontConfig? _cachedPublished;

  Future<StorefrontConfig> loadPublished({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedPublished != null) {
      return _cachedPublished!;
    }

    final client = supabaseClient;
    if (client == null) {
      _cachedPublished = _demoPublished;
      return _demoPublished;
    }

    try {
      final response = await client.rpc('get_published_storefront_config');
      final config = StorefrontConfig.fromJson(
        response is Map<String, dynamic>
            ? response
            : response is Map
                ? Map<String, dynamic>.from(response)
                : null,
      );
      config.validate();
      _cachedPublished = config;
      return config;
    } catch (_) {
      _cachedPublished = StorefrontDefaults.bundled;
      return StorefrontDefaults.bundled;
    }
  }

  Future<StorefrontAdminState> loadAdminState() async {
    final client = supabaseClient;
    if (client == null) {
      return StorefrontAdminState(
        draftConfig: _demoDraft,
        publishedConfig: _demoPublished,
        updatedAt: _demoUpdatedAt,
        publishedAt: _demoUpdatedAt,
        hasDraftChanges: _encode(_demoDraft) != _encode(_demoPublished),
      );
    }

    final response = await client.rpc('get_storefront_admin_state');
    if (response is! Map) {
      throw StateError('Invalid storefront admin state');
    }
    return StorefrontAdminState.fromRemote(Map<String, dynamic>.from(response));
  }

  Future<DateTime> saveDraft({
    required StorefrontConfig config,
    DateTime? expectedUpdatedAt,
  }) async {
    config.validate();
    final client = supabaseClient;
    if (client == null) {
      _demoDraft = config;
      _demoUpdatedAt = DateTime.now().toUtc();
      return _demoUpdatedAt;
    }

    try {
      final response = await client.rpc(
        'admin_save_storefront_draft',
        params: {
          'p_config': config.toJson(),
          'p_expected_updated_at': utcIsoOrNull(expectedUpdatedAt),
        },
      );
      _cachedPublished = null;
      return _parseTimestamp(response) ?? DateTime.now().toUtc();
    } catch (error) {
      rethrowIfStaleWrite(error);
      rethrow;
    }
  }

  /// Publishes the storefront. When [config] is provided, draft is saved and
  /// published atomically in one RPC (avoids save→publish concurrency races).
  Future<DateTime> publish({
    StorefrontConfig? config,
    DateTime? expectedUpdatedAt,
  }) async {
    if (config != null) {
      config.validate();
    }
    final client = supabaseClient;
    if (client == null) {
      if (config != null) {
        _demoDraft = config;
      }
      _demoPublished = _demoDraft;
      _demoUpdatedAt = DateTime.now().toUtc();
      _cachedPublished = _demoPublished;
      return _demoUpdatedAt;
    }

    try {
      final response = await client.rpc(
        'admin_publish_storefront',
        params: {
          'p_expected_updated_at': utcIsoOrNull(expectedUpdatedAt),
          if (config != null) 'p_draft_config': config.toJson(),
        },
      );
      _cachedPublished = null;
      return _parseTimestamp(response) ?? DateTime.now().toUtc();
    } catch (error) {
      rethrowIfStaleWrite(error);
      rethrow;
    }
  }

  Future<DateTime> resetDraft({DateTime? expectedUpdatedAt}) async {
    final client = supabaseClient;
    if (client == null) {
      _demoDraft = StorefrontDefaults.bundled;
      _demoUpdatedAt = DateTime.now().toUtc();
      return _demoUpdatedAt;
    }

    try {
      final response = await client.rpc(
        'admin_reset_storefront_draft',
        params: {
          'p_expected_updated_at': utcIsoOrNull(expectedUpdatedAt),
        },
      );
      return _parseTimestamp(response) ?? DateTime.now().toUtc();
    } catch (error) {
      rethrowIfStaleWrite(error);
      rethrow;
    }
  }

  void rememberDemoPublished(StorefrontConfig config) {
    if (!AppConfig.isDemoMode && supabaseClient != null) return;
    _demoPublished = config;
    _cachedPublished = config;
  }

  String _encode(StorefrontConfig config) => config.encode();

  DateTime? _parseTimestamp(Object? raw) {
    if (raw is DateTime) return raw.toUtc();
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toUtc();
    }
    return null;
  }
}
