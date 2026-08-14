import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../models/app_notification.dart';
import '../models/notification_campaign_summary.dart';
import '../remote/supabase_clients.dart';

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) => NotificationsRepository());

final unreadNotificationsCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(notificationsRepositoryProvider).unreadCount(),
);

class NotificationsRepository {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final List<AppNotification> _demoNotifications = [
    AppNotification(
      id: 'demo-notification-order',
      type: 'order_status',
      title: 'تم تأكيد الطلب',
      body: 'تم تأكيد الطلب التجريبي وسيبدأ التجهيز قريباً.',
      payload: const {'order_id': 'o1001'},
      createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
    ),
    AppNotification(
      id: 'demo-notification-product',
      type: 'product_campaign',
      title: 'منتجات جديدة',
      body: 'تمت إضافة أصناف جديدة إلى الكتالوج التجريبي.',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      readAt: DateTime.now().subtract(const Duration(hours: 20)),
    ),
  ];
  final List<NotificationCampaignSummary> _demoCampaigns = [];
  final Map<String, int> _demoCampaignRecipientCounts = {};
  final Map<String, String> _demoCampaignFingerprints = {};

  Future<List<AppNotification>> list({int limit = 50}) async {
    final client = supabaseClient;
    if (client == null) {
      return [..._demoNotifications]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    final rows = await client
        .from('notifications')
        .select('id, type, title, body, payload, read_at, created_at')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map<AppNotification>((row) => AppNotification.fromSupabase(row))
        .toList();
  }

  Future<int> unreadCount() async {
    final client = supabaseClient;
    if (client != null) {
      return client.from('notifications').count().isFilter('read_at', null);
    }

    return _demoNotifications
        .where((notification) => !notification.isRead)
        .length;
  }

  Future<void> markRead(String notificationId) async {
    final client = supabaseClient;
    if (client != null) {
      await client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()}).eq(
              'id', notificationId);
      return;
    }

    final index = _demoNotifications
        .indexWhere((notification) => notification.id == notificationId);
    if (index != -1) {
      _demoNotifications[index] =
          _demoNotifications[index].copyWith(readAt: DateTime.now());
    }
  }

  void addDemoOrderStatus({
    required String orderId,
    required String statusLabel,
  }) {
    if (supabaseClient != null) return;
    _demoNotifications.insert(
      0,
      AppNotification(
        id: 'demo-order-status-${const Uuid().v4()}',
        type: 'order_status',
        title: 'تحديث حالة الطلب',
        body: 'أصبحت حالة طلبك: $statusLabel.',
        payload: {'order_id': orderId},
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    required String appVersion,
    String? deviceId,
    String? deviceLabel,
  }) async {
    final client = supabaseClient;
    if (client == null || token.isEmpty) return;

    final response = await client.functions.invoke(
      AppConfig.registerDeviceTokenFunction,
      body: {
        'token': token,
        'platform': platform,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        'device_label': deviceLabel,
        'app_version': appVersion,
        'locale': 'ar_LY',
      },
    );
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      throw StateError('Device token registration was not accepted.');
    }
  }

  Future<void> unregisterDeviceToken({
    required String token,
    String? deviceId,
  }) async {
    final client = supabaseClient;
    if (client == null || (token.isEmpty && (deviceId?.isEmpty ?? true))) {
      return;
    }
    final response = await client.functions.invoke(
      AppConfig.unregisterDeviceTokenFunction,
      body: {
        if (token.isNotEmpty) 'token': token,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
      },
    );
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      throw StateError('Device token removal was not accepted.');
    }
  }

  Future<int> sendCampaign({
    required String idempotencyKey,
    required String title,
    required String body,
    required String audienceType,
    List<String> profileIds = const [],
    String? productId,
  }) async {
    final campaignId = validateCampaignIdempotencyKey(idempotencyKey);
    final client = supabaseClient;
    if (client == null) {
      final fingerprint = campaignFingerprint(
        title: title,
        body: body,
        audienceType: audienceType,
        profileIds: profileIds,
        productId: productId,
      );
      final existingCount = _demoCampaignRecipientCounts[campaignId];
      if (existingCount != null) {
        if (_demoCampaignFingerprints[campaignId] != fingerprint) {
          throw StateError(
            'Campaign idempotency key was reused for different content.',
          );
        }
        return existingCount;
      }

      final recipientCount =
          audienceType == 'selected_profiles' ? profileIds.length : 3;
      final createdAt = DateTime.now();
      _demoNotifications.insert(
        0,
        AppNotification(
          id: 'demo-campaign-$campaignId',
          type: 'product_campaign',
          title: title,
          body: body,
          payload: {
            if (productId != null && productId.isNotEmpty)
              'product_id': productId,
          },
          createdAt: createdAt,
        ),
      );
      _demoCampaignRecipientCounts[campaignId] = recipientCount;
      _demoCampaignFingerprints[campaignId] = fingerprint;
      _demoCampaigns.insert(
        0,
        NotificationCampaignSummary(
          id: campaignId,
          title: title,
          body: body,
          audience: campaignAudiencePayload(
            audienceType: audienceType,
            profileIds: profileIds,
          ),
          recipientCount: recipientCount,
          completedCount: recipientCount,
          pendingCount: 0,
          retryingCount: 0,
          deadCount: 0,
          deviceSentCount: 0,
          createdAt: createdAt,
        ),
      );
      return recipientCount;
    }

    final audience = campaignAudiencePayload(
      audienceType: audienceType,
      profileIds: profileIds,
    );
    final response = await client.functions.invoke(
      AppConfig.sendNotificationCampaignFunction,
      body: {
        'idempotency_key': campaignId,
        'title': title,
        'body': body,
        'type': 'product_campaign',
        'audience': audience,
        'payload': {
          if (productId != null && productId.isNotEmpty)
            'product_id': productId,
        },
      },
    );
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      throw StateError('Campaign delivery was not accepted.');
    }
    return (data['recipient_count'] as num?)?.toInt() ?? 0;
  }

  Future<List<NotificationCampaignSummary>> listCampaignSummaries({
    int limit = 10,
  }) async {
    final client = supabaseClient;
    if (client == null) {
      return _demoCampaigns.take(limit).toList(growable: false);
    }

    final rows = await client.rpc(
      'notification_campaign_summaries',
      params: {'p_limit': limit.clamp(1, 50)},
    );
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => NotificationCampaignSummary.fromSupabase(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  static String newCampaignIdempotencyKey() => const Uuid().v4();

  static String validateCampaignIdempotencyKey(String value) {
    final key = value.trim();
    if (!_uuidPattern.hasMatch(key)) {
      throw ArgumentError.value(
        value,
        'idempotencyKey',
        'Campaign idempotency key must be a UUID.',
      );
    }
    return key;
  }

  static String campaignFingerprint({
    required String title,
    required String body,
    required String audienceType,
    List<String> profileIds = const [],
    String? productId,
  }) {
    final sortedProfileIds = [...profileIds]..sort();
    return jsonEncode({
      'title': title.trim(),
      'body': body.trim(),
      'audience_type': audienceType,
      'profile_ids': sortedProfileIds,
      'product_id': productId?.trim() ?? '',
    });
  }

  /// Converts the UI's explicit audience choices into the Edge Function
  /// contract. Keeping this mapping here prevents display labels becoming API
  /// values and makes the server boundary auditable.
  static Map<String, dynamic> campaignAudiencePayload({
    required String audienceType,
    List<String> profileIds = const [],
  }) {
    return switch (audienceType) {
      'all_customers' => const {'type': 'role', 'role': 'customer'},
      'all_staff' => const {
          'type': 'roles',
          'roles': ['admin', 'staff'],
        },
      'selected_profiles' when profileIds.isNotEmpty => {
          'type': 'profile_ids',
          'profile_ids': ([...profileIds]..sort()).toSet().toList(),
        },
      'selected_profiles' => throw ArgumentError.value(
          profileIds,
          'profileIds',
          'A selected audience requires at least one profile.',
        ),
      _ => throw ArgumentError.value(
          audienceType,
          'audienceType',
          'Unsupported notification audience.',
        ),
    };
  }
}
