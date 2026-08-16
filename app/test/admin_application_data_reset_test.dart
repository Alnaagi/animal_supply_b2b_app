import 'package:animal_supply_b2b/src/core/security/destructive_confirm_phrase.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production reset invokes the admin-only function with RESET', () async {
    String? invoked;
    Map<String, dynamic>? body;
    final repository = AdminRepository(
      demoCustomers: const [],
      edgeFunctionInvoker: (functionName, payload) async {
        invoked = functionName;
        body = payload;
        return {
          'ok': true,
          'data': {
            'reset': true,
            'preserved_admin_id': 'admin-1',
            'truncated_tables': ['products', 'orders', 'business_customers'],
            'customer_profiles_deleted': 2,
            'customer_auth_users_deleted': 2,
          },
        };
      },
    );

    final result = await repository.resetProductionApplicationData();
    expect(invoked, 'admin-reset-application-data');
    expect(body, {'confirm_phrase': DestructiveConfirmPhrase.requiredPhrase});
    expect(result.reset, isTrue);
    expect(result.preservedAdminId, 'admin-1');
    expect(result.truncatedTables, contains('products'));
    expect(result.customerAuthUsersDeleted, 2);
  });

  test('rejected production reset payloads do not look successful', () async {
    final repository = AdminRepository(
      demoCustomers: const [],
      edgeFunctionInvoker: (functionName, body) async {
        return {
          'ok': false,
          'error': {'code': 'FORBIDDEN'},
        };
      },
    );

    expect(
      repository.resetProductionApplicationData(),
      throwsA(isA<FormatException>()),
    );
  });
}
