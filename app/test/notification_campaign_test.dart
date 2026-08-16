import 'package:animal_supply_b2b/src/data/repositories/notifications_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('notification campaign audience contract', () {
    test('maps all active customers to the customer role', () {
      expect(
        NotificationsRepository.campaignAudiencePayload(
          audienceType: 'all_customers',
        ),
        {'type': 'role', 'role': 'customer'},
      );
    });

    test('maps staff broadcast to both active operations roles', () {
      expect(
        NotificationsRepository.campaignAudiencePayload(
          audienceType: 'all_staff',
        ),
        {
          'type': 'roles',
          'roles': ['admin', 'staff'],
        },
      );
    });

    test('maps selected users to profile IDs without changing identifiers', () {
      expect(
        NotificationsRepository.campaignAudiencePayload(
          audienceType: 'selected_profiles',
          profileIds: const [
            '11111111-1111-4111-8111-111111111111',
            '22222222-2222-4222-8222-222222222222',
          ],
        ),
        {
          'type': 'profile_ids',
          'profile_ids': [
            '11111111-1111-4111-8111-111111111111',
            '22222222-2222-4222-8222-222222222222',
          ],
        },
      );
    });

    test('maps a missing campaign function to Arabic copy', () {
      const error = FunctionException(
        status: 404,
        details: {
          'code': 'NOT_FOUND',
          'message': 'Requested function was not found',
        },
      );
      expect(
        NotificationsRepository.campaignFailureMessageAr(error),
        contains('غير منشورة'),
      );
    });

    test('maps a disallowed origin to Arabic copy', () {
      const error = FunctionException(
        status: 403,
        details: {
          'ok': false,
          'error': {'code': 'ORIGIN_NOT_ALLOWED', 'message': 'blocked'},
        },
      );
      expect(
        NotificationsRepository.campaignFailureMessageAr(error),
        contains('هذا الموقع'),
      );
    });
  });

  group('notification campaign retry safety', () {
    const campaignId = '11111111-1111-4111-8111-111111111111';

    test('accepts a UUID idempotency key and rejects unsafe values', () {
      expect(
        NotificationsRepository.validateCampaignIdempotencyKey(campaignId),
        campaignId,
      );
      expect(
        () => NotificationsRepository.validateCampaignIdempotencyKey(
          'campaign-1',
        ),
        throwsArgumentError,
      );
    });

    test('fingerprint is stable across selected-profile ordering', () {
      final first = NotificationsRepository.campaignFingerprint(
        title: 'عرض جديد',
        body: 'وصلت منتجات جديدة',
        audienceType: 'selected_profiles',
        profileIds: const ['profile-b', 'profile-a'],
      );
      final second = NotificationsRepository.campaignFingerprint(
        title: ' عرض جديد ',
        body: 'وصلت منتجات جديدة',
        audienceType: 'selected_profiles',
        profileIds: const ['profile-a', 'profile-b'],
      );
      expect(first, second);
    });

    test('demo retries converge to one campaign history row', () async {
      final repository = NotificationsRepository();

      final first = await repository.sendCampaign(
        idempotencyKey: campaignId,
        title: 'عرض جديد',
        body: 'وصلت منتجات جديدة',
        audienceType: 'all_customers',
      );
      final retry = await repository.sendCampaign(
        idempotencyKey: campaignId,
        title: 'عرض جديد',
        body: 'وصلت منتجات جديدة',
        audienceType: 'all_customers',
      );
      final history = await repository.listCampaignSummaries();

      expect(first, retry);
      expect(history, hasLength(1));
      expect(history.single.id, campaignId);
      expect(history.single.recipientCount, first);
    });

    test('demo rejects reuse of one key for different content', () async {
      final repository = NotificationsRepository();
      await repository.sendCampaign(
        idempotencyKey: campaignId,
        title: 'العنوان الأول',
        body: 'نص الحملة',
        audienceType: 'all_customers',
      );

      expect(
        () => repository.sendCampaign(
          idempotencyKey: campaignId,
          title: 'عنوان مختلف',
          body: 'نص الحملة',
          audienceType: 'all_customers',
        ),
        throwsStateError,
      );
    });
  });

  test('demo order status produces a customer-visible notification', () async {
    final repository = NotificationsRepository();
    repository.addDemoOrderStatus(
      orderId: 'demo-order-42',
      statusLabel: 'قيد التجهيز',
    );

    final notifications = await repository.list();
    expect(notifications.first.orderId, 'demo-order-42');
    expect(notifications.first.body, contains('قيد التجهيز'));
    expect(notifications.first.isRead, isFalse);
  });

  test('inbox RPC payloads accept a bare array or a wrapped data list', () {
    expect(
      NotificationsRepository.parseInboxRpcPayload([
        {'id': 'n1', 'title': 'طلب جديد'},
      ]),
      [
        {'id': 'n1', 'title': 'طلب جديد'},
      ],
    );
    expect(
      NotificationsRepository.parseInboxRpcPayload({
        'data': [
          {'id': 'n2', 'title': 'عرض'},
        ],
      }),
      [
        {'id': 'n2', 'title': 'عرض'},
      ],
    );
    expect(NotificationsRepository.parseInboxRpcPayload('oops'), isNull);
  });
}
