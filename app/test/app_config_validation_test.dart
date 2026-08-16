import 'dart:convert';

import 'package:animal_supply_b2b/src/core/config/app_config_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Supabase public build configuration', () {
    test('accepts a publishable key for a real HTTPS project', () {
      final result = validateSupabasePublicConfig(
        url: 'https://client-project.supabase.co',
        publicKey: 'sb_publishable_${_repeat('a', 32)}',
        allowLocalUrl: false,
      );

      expect(result.isValid, isTrue);
    });

    test('accepts a legacy anon JWT and rejects service-role JWTs', () {
      final anon = validateSupabasePublicConfig(
        url: 'https://client-project.supabase.co',
        publicKey: _jwtWithRole('anon'),
        allowLocalUrl: false,
      );
      final serviceRole = validateSupabasePublicConfig(
        url: 'https://client-project.supabase.co',
        publicKey: _jwtWithRole('service_role'),
        allowLocalUrl: false,
      );

      expect(anon.isValid, isTrue);
      expect(serviceRole.isValid, isFalse);
      expect(serviceRole.messageAr, contains('service_role'));
    });

    test('rejects secret keys, placeholders, and unsafe production URLs', () {
      for (final input in [
        (
          url: 'http://client-project.supabase.co',
          key: 'sb_publishable_${_repeat('a', 32)}',
        ),
        (
          url: 'https://localhost:54321',
          key: 'sb_publishable_${_repeat('a', 32)}',
        ),
        (
          url: 'https://client-project.supabase.co',
          key: 'sb_secret_${_repeat('a', 32)}',
        ),
        (
          url: 'https://YOUR_PROJECT.supabase.co',
          key: 'YOUR_PUBLIC_ANON_KEY',
        ),
      ]) {
        expect(
          validateSupabasePublicConfig(
            url: input.url,
            publicKey: input.key,
            allowLocalUrl: false,
          ).isValid,
          isFalse,
        );
      }
    });
  });

  group('Firebase public client configuration', () {
    const base = (
      apiKey: 'AIza-real-public-client-key',
      projectId: 'client-project',
      senderId: '1234567890',
    );

    test('requires the platform-specific app id and web VAPID key', () {
      expect(
        firebaseClientConfigurationIssueAr(
          platform: FirebaseClientPlatform.web,
          apiKey: base.apiKey,
          projectId: base.projectId,
          messagingSenderId: base.senderId,
          webAppId: '',
          androidAppId: '',
          iosAppId: '',
          webVapidKey: '',
        ),
        isNotNull,
      );
      expect(
        firebaseClientConfigurationIssueAr(
          platform: FirebaseClientPlatform.android,
          apiKey: base.apiKey,
          projectId: base.projectId,
          messagingSenderId: base.senderId,
          webAppId: '',
          androidAppId: '1:1234567890:android:abc123',
          iosAppId: '',
          webVapidKey: '',
        ),
        isNull,
      );
    });

    test('rejects placeholder base configuration', () {
      expect(
        firebaseClientConfigurationIssueAr(
          platform: FirebaseClientPlatform.ios,
          apiKey: 'YOUR_FIREBASE_KEY',
          projectId: base.projectId,
          messagingSenderId: base.senderId,
          webAppId: '',
          androidAppId: '',
          iosAppId: '1:1234567890:ios:abc123',
          webVapidKey: '',
        ),
        isNotNull,
      );
    });

    test('explains OS tray works without Firebase while the tab can run', () {
      expect(
        firebaseClosedAppRequirementAr(configured: false),
        contains('شريط إشعارات'),
      );
      expect(
        firebaseClosedAppRequirementAr(configured: false),
        contains('العملية بالكامل'),
      );
      expect(
        firebaseClosedAppRequirementAr(configured: false),
        contains('لا نستخدم Firebase حالياً'),
      );
      expect(
        firebaseClosedAppRequirementAr(configured: true),
        contains('لا نستخدم Firebase حالياً'),
      );
      expect(
        firebaseClosedAppRequirementAr(configured: true),
        isNot(contains('بعد تسجيل الجهاز')),
      );
    });
  });

  test('public app origin accepts only a real HTTPS origin', () {
    expect(validatePublicAppOriginAr('https://shop.client.ly'), isNull);
    for (final value in [
      'http://shop.client.ly',
      'https://localhost:8765',
      'https://shop.client.ly/invite',
      'https://user:secret@shop.client.ly',
    ]) {
      expect(validatePublicAppOriginAr(value), isNotNull);
    }
  });
}

String _jwtWithRole(String role) {
  String part(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'role': role, 'exp': 4102444800})}.signature';
}

String _repeat(String value, int count) => List.filled(count, value).join();
