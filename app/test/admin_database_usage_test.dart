import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote database usage reads percent from the admin function', () async {
    String? invoked;
    final repository = AdminRepository(
      demoCustomers: const [],
      edgeFunctionInvoker: (functionName, body) async {
        invoked = functionName;
        expect(body, isEmpty);
        return {
          'ok': true,
          'data': {
            'used_bytes': 268435456,
            'quota_bytes': 536870912,
            'percent': 50,
            'source': 'postgres',
          },
        };
      },
    );

    final usage = await repository.remoteDatabaseUsage();
    expect(invoked, 'admin-database-usage');
    expect(usage.percent, 50);
    expect(usage.usedBytes, 268435456);
    expect(usage.quotaBytes, 536870912);
  });

  test('rejected usage payloads do not look like a live quota', () async {
    final repository = AdminRepository(
      demoCustomers: const [],
      edgeFunctionInvoker: (functionName, body) async {
        return {
          'ok': false,
          'error': {'code': 'FORBIDDEN'},
        };
      },
    );

    expect(repository.remoteDatabaseUsage(), throwsA(isA<FormatException>()));
  });
}
