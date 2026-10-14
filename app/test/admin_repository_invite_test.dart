import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InviteResult.fromFunctionResponse', () {
    test('uses the server one-time reset link from nested snake-case data', () {
      const secureLink =
          'https://app.example.ly/invite?token=server-token&client=shop-1';
      final result = InviteResult.fromFunctionResponse(
        {
          'ok': true,
          'data': {
            'username': 'shop-1',
            'temporary_password': 'New-Password-42!',
            'invite_link': secureLink,
            'whatsapp_message': 'افتح الرابط الآمن: $secureLink',
          },
        },
        fallbackUsername: 'fallback-shop',
        customerPhone: '+218910000001',
      );

      expect(result.username, 'shop-1');
      expect(result.temporaryPassword, 'New-Password-42!');
      expect(result.inviteLink, secureLink);
      expect(result.whatsappMessage, contains(secureLink));
    });

    test('accepts the compatibility camel-case response fields', () {
      const secureLink =
          'https://app.example.ly/invite?token=compat-token&client=shop-2';
      final result = InviteResult.fromFunctionResponse(
        {
          'temporaryPassword': 'Compat-Password-42!',
          'inviteLink': secureLink,
          'whatsappMessage': 'رابط العميل: $secureLink',
        },
        fallbackUsername: 'shop-2',
        customerPhone: '+218910000002',
      );

      expect(result.username, 'shop-2');
      expect(result.inviteLink, secureLink);
    });

    test('fails closed when the server does not return an invite link', () {
      expect(
        () => InviteResult.fromFunctionResponse(
          {
            'temporaryPassword': 'Missing-Link-42!',
            'whatsappMessage': 'No link returned',
          },
          fallbackUsername: 'shop-3',
          customerPhone: '+218910000003',
        ),
        throwsStateError,
      );
    });

    test('rejects a non-HTTPS or password-bearing server link', () {
      for (final inviteLink in [
        'animalsupplyb2b://invite?token=server-token',
        'https://app.example.ly/invite?token=server-token&password=secret',
      ]) {
        expect(
          () => InviteResult.fromFunctionResponse(
            {
              'temporary_password': 'Unsafe-Link-42!',
              'invite_link': inviteLink,
              'whatsapp_message': 'رابط غير صالح: $inviteLink',
            },
            fallbackUsername: 'shop-4',
            customerPhone: '+218910000004',
          ),
          throwsStateError,
        );
      }
    });
  });

  group('AdminRepository.resetCustomerPassword', () {
    test('remote reset uses user_id and returns only the server result',
        () async {
      String? invokedFunction;
      Map<String, dynamic>? invokedBody;
      final repository = AdminRepository(
        edgeFunctionInvoker: (functionName, body) async {
          invokedFunction = functionName;
          invokedBody = body;
          return _secureResetResponse(
            username: 'shop-profile',
            password: 'Server-Password-42!',
            token: 'profile-reset-token',
          );
        },
      );

      final result = await repository.resetCustomerPassword(
        const BusinessCustomer(
          id: '10000000-0000-4000-8000-000000000001',
          profileId: '20000000-0000-4000-8000-000000000001',
          businessName: 'متجر الاختبار',
          username: 'shop-profile',
          phone: '+218910000001',
        ),
      );

      expect(invokedFunction, 'admin-reset-customer-password');
      expect(invokedBody, {
        'user_id': '20000000-0000-4000-8000-000000000001',
      });
      expect(result.temporaryPassword, 'Server-Password-42!');
      expect(result.inviteLink, startsWith('https://'));
      expect(result.inviteLink, isNot(contains('reset_demo')));
    });

    test('remote reset falls back to customer_id, never demo credentials',
        () async {
      Map<String, dynamic>? invokedBody;
      final repository = AdminRepository(
        edgeFunctionInvoker: (functionName, body) async {
          invokedBody = body;
          return _secureResetResponse(
            username: 'shop-customer',
            password: 'Server-Password-84!',
            token: 'customer-reset-token',
          );
        },
      );

      final result = await repository.resetCustomerPassword(
        const BusinessCustomer(
          id: '30000000-0000-4000-8000-000000000001',
          businessName: 'متجر بلا ملف محمّل',
          username: 'shop-customer',
          phone: '+218910000002',
        ),
      );

      expect(invokedBody, {
        'customer_id': '30000000-0000-4000-8000-000000000001',
      });
      expect(result.temporaryPassword, 'Server-Password-84!');
      expect(result.temporaryPassword, isNot('Temp-48291!'));
      expect(result.inviteLink, isNot(contains('reset_demo')));
    });

    test('remote reset fails closed when neither server identifier exists',
        () async {
      var invoked = false;
      final repository = AdminRepository(
        edgeFunctionInvoker: (functionName, body) async {
          invoked = true;
          return _secureResetResponse(
            username: 'invalid',
            password: 'Server-Password-99!',
            token: 'invalid-reset-token',
          );
        },
      );

      await expectLater(
        repository.resetCustomerPassword(
          const BusinessCustomer(
            id: 'new',
            businessName: 'عميل غير محفوظ',
            username: 'unsaved-customer',
          ),
        ),
        throwsStateError,
      );
      expect(invoked, isFalse);
    });
  });

  group('AdminRepository.setCustomerPassword', () {
    test(
        'sends the chosen password to the reset function without invite fields',
        () async {
      String? invokedFunction;
      Map<String, dynamic>? invokedBody;
      final repository = AdminRepository(
        edgeFunctionInvoker: (functionName, body) async {
          invokedFunction = functionName;
          invokedBody = body;
          return {
            'ok': true,
            'data': {
              'username': 'shop-profile',
              'password_updated': true,
            },
          };
        },
      );

      await repository.setCustomerPassword(
        const BusinessCustomer(
          id: '10000000-0000-4000-8000-000000000001',
          profileId: '20000000-0000-4000-8000-000000000001',
          businessName: 'متجر الاختبار',
          username: 'shop-profile',
          phone: '+218910000001',
        ),
        password: 'Admin-Set-42!',
      );

      expect(invokedFunction, 'admin-reset-customer-password');
      expect(invokedBody, {
        'user_id': '20000000-0000-4000-8000-000000000001',
        'password': 'Admin-Set-42!',
      });
      expect(invokedBody, isNot(contains('invite_link')));
    });

    test('skips the server call when the password field is empty', () async {
      var invoked = false;
      final repository = AdminRepository(
        edgeFunctionInvoker: (functionName, body) async {
          invoked = true;
          return const <String, dynamic>{};
        },
      );

      await repository.setCustomerPassword(
        const BusinessCustomer(
          id: '10000000-0000-4000-8000-000000000001',
          profileId: '20000000-0000-4000-8000-000000000001',
          businessName: 'متجر الاختبار',
          username: 'shop-profile',
        ),
        password: '   ',
      );

      expect(invoked, isFalse);
    });
  });
}

Map<String, dynamic> _secureResetResponse({
  required String username,
  required String password,
  required String token,
}) {
  final inviteLink =
      'https://app.example.ly/invite?token=$token&client=$username';
  return {
    'ok': true,
    'data': {
      'username': username,
      'temporary_password': password,
      'invite_link': inviteLink,
      'whatsapp_message': 'افتح الرابط الآمن: $inviteLink',
    },
  };
}
