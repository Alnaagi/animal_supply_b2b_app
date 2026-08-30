import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../models/app_notification.dart';
import '../models/notification_campaign_summary.dart';
import '../remote/supabase_clients.dart';

class NotificationCampaignException implements Exception {
  const NotificationCampaignException(this.messageAr, {this.code = ''});

  final String messageAr;
  final String code;

  @override
  String toString() => messageAr;
}

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) => NotificationsRepository());

final unreadNotificationsCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(notificationsRepositoryProvider).unreadCount(),
);

/// Bumped when a new in-app notification is observed so open inboxes reload.
final notificationInboxEpochProvider = StateProvider<int>((ref) => 0);

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

    final rows = await _inboxRows(client, limit);
    return rows.map(AppNotification.fromSupabase).toList(growable: false);
  }

  Future<int> unreadCount() async {
    final client = supabaseClient;
    if (client == null) {
      return _demoNotifications
          .where((notification) => !notification.isRead)
          .length;
    }

    try {
      final count = await client.rpc('unread_notification_count');
      if (count is num) return count.toInt();
    } catch (_) {}

    final rows = await _inboxRows(client, 100);
    return rows.where((row) => row['read_at'] == null).length;
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

  Future<int> markAllRead() async {
    final client = supabaseClient;
    if (client != null) {
      try {
        final updated = await client.rpc('mark_all_my_notifications_read');
        if (updated is num) return updated.toInt();
      } catch (_) {}

      final unread = await client
          .from('notifications')
          .select('id')
          .isFilter('read_at', null);
      final ids = unread
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (ids.isEmpty) return 0;
      await client.from('notifications').update(
          {'read_at': DateTime.now().toIso8601String()}).inFilter('id', ids);
      return ids.length;
    }

    var marked = 0;
    final readAt = DateTime.now();
    for (var index = 0; index < _demoNotifications.length; index++) {
      if (_demoNotifications[index].isRead) continue;
      _demoNotifications[index] =
          _demoNotifications[index].copyWith(readAt: readAt);
      marked++;
    }
    return marked;
  }

  Future<List<Map<String, dynamic>>> _inboxRows(
    SupabaseClient client,
    int limit,
  ) async {
    final clampedLimit = limit.clamp(1, 100);
    try {
      final parsed = parseInboxRpcPayload(
        await client.rpc(
          'list_my_notifications',
          params: {'p_limit': clampedLimit},
        ),
      );
      if (parsed != null) return parsed;
    } catch (_) {}

    final userId = client.auth.currentUser?.id;
    var query = client
        .from('notifications')
        .select('id, type, title, body, payload, read_at, created_at');
    if (userId != null && userId.isNotEmpty) {
      query = query.eq('recipient_profile_id', userId);
    }
    final rows =
        await query.order('created_at', ascending: false).limit(clampedLimit);
    return [
      for (final row in rows) Map<String, dynamic>.from(row),
    ];
  }

  /// PostgREST table RPCs usually return a JSON array. Some gateways wrap it.
  static List<Map<String, dynamic>>? parseInboxRpcPayload(Object? rows) {
    if (rows is List) {
      return [
        for (final row in rows)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
    }
    if (rows is Map) {
      final nested = rows['data'] ?? rows['result'];
      if (nested is List) return parseInboxRpcPayload(nested);
    }
    return null;
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
    String? installationId,
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
        if (installationId != null && installationId.isNotEmpty)
          'installation_id': installationId,
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
    try {
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
        throw NotificationCampaignException(
          campaignFailureMessageAr(
              data ?? 'Campaign delivery was not accepted.'),
        );
      }
      return (data['recipient_count'] as num?)?.toInt() ?? 0;
    } on NotificationCampaignException {
      rethrow;
    } on FunctionException catch (error) {
      throw NotificationCampaignException(
        campaignFailureMessageAr(error),
        code: _campaignErrorCode(error),
      );
    } catch (error) {
      throw NotificationCampaignException(campaignFailureMessageAr(error));
    }
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

  static String campaignFailureMessageAr(Object error) {
    if (error is NotificationCampaignException) return error.messageAr;
    final code = _campaignErrorCode(error);
    final status = error is FunctionException ? error.status : null;
    if (status == 404 || code == 'NOT_FOUND') {
      return 'تعذر الإرسال لأن خدمة الحملات غير منشورة على الخادم.';
    }
    return switch (code) {
      'ORIGIN_NOT_ALLOWED' =>
        'تعذر الإرسال من هذا الموقع. راجع إعداد النطاق المسموح.',
      'NO_CAMPAIGN_RECIPIENTS' => 'لا يوجد مستلمون مطابقون لهذا الجمهور.',
      'RATE_LIMITED' => 'تم تجاوز حد الإرسال. حاول بعد قليل.',
      'AUTH_REQUIRED' ||
      'INVALID_SESSION' ||
      'ADMIN_AUTH_REQUIRED' =>
        'انتهت الجلسة أو لا توجد صلاحية إرسال. أعد تسجيل الدخول.',
      'CAMPAIGN_PRODUCT_UNAVAILABLE' => 'المنتج المختار غير متاح أو مؤرشف.',
      'SERVER_CONFIGURATION_ERROR' =>
        'إعداد الخادم ناقص. الإشعارات داخل التطبيق تتطلب نشر دالة الإرسال.',
      _ => _looksLikeBrowserCors(error)
          ? 'تعذر الاتصال بخدمة الإرسال من المتصفح. تحقق من الاتصال ثم أعد المحاولة.'
          : 'تعذر إرسال الإشعار. تحقق من الاتصال والصلاحيات.',
    };
  }

  static String _campaignErrorCode(Object error) {
    if (error is NotificationCampaignException) return error.code;
    Object? current = error is FunctionException ? error.details : error;
    if (current is String && current.trim().isNotEmpty) {
      try {
        current = jsonDecode(current);
      } catch (_) {}
    }
    if (current is Map) {
      final nested = current['error'];
      final nestedCode =
          nested is Map ? nested['code']?.toString().trim() ?? '' : '';
      final rootCode = current['code']?.toString().trim() ?? '';
      if (nestedCode.isNotEmpty) return nestedCode;
      if (rootCode.isNotEmpty) return rootCode;
    }
    return '';
  }

  static bool _looksLikeBrowserCors(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('xmlhttprequest') ||
        text.contains('failed to fetch') ||
        text.contains('cors') ||
        text.contains('origin_not_allowed');
  }

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
