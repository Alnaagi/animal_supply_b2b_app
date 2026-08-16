import 'package:animal_supply_b2b/src/data/models/database_usage.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/dashboard_fullness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo fullness uses catalog+orders against a labelled demo cap', () {
    final estimate = estimateDashboardFullness(
      demoOrOffline: true,
      productCount: 40,
      orderCount: 2,
    );

    expect(estimate.kind, DashboardFullnessKind.demoCatalog);
    expect(estimate.isDemoEstimate, isTrue);
    expect(estimate.isOperationalDbQuota, isFalse);
    expect(estimate.titleAr, 'امتلاء قاعدة البيانات');
    expect(estimate.captionAr, contains('تجريبي'));
    expect(estimate.captionAr, contains('غير تشغيلي'));
    expect(estimate.percent, 36);
  });

  test('demo fullness clamps at 100 percent', () {
    final estimate = estimateDashboardFullness(
      demoOrOffline: true,
      productCount: 800,
      orderCount: 400,
    );
    expect(estimate.percent, 100);
    expect(estimate.isOperationalDbQuota, isFalse);
    expect(estimate.isDemoEstimate, isTrue);
  });

  test('failed remote usage is a labelled local fallback, not a live quota', () {
    final estimate = estimateDashboardFullness(
      demoOrOffline: false,
      productCount: 50,
      orderCount: 999,
    );

    expect(estimate.kind, DashboardFullnessKind.localCacheFallback);
    expect(estimate.isFallbackEstimate, isTrue);
    expect(estimate.isOperationalDbQuota, isFalse);
    expect(estimate.titleAr, 'امتلاء قاعدة البيانات');
    expect(estimate.captionAr, contains('تقدير محلي'));
    expect(estimate.percent, 25);
  });

  test('empty local fallback stays at zero and stays labelled', () {
    final estimate = estimateDashboardFullness(
      demoOrOffline: false,
      productCount: 0,
    );
    expect(estimate.percent, 0);
    expect(estimate.isFallbackEstimate, isTrue);
    expect(estimate.isOperationalDbQuota, isFalse);
  });

  test('operational usage uses the server percent and live caption', () {
    final estimate = operationalDatabaseFullness(
      const DatabaseUsageSnapshot(
        usedBytes: 250 * 1024 * 1024,
        quotaBytes: 500 * 1024 * 1024,
        percent: 50,
      ),
    );
    expect(estimate.kind, DashboardFullnessKind.operationalDb);
    expect(estimate.isOperationalDbQuota, isTrue);
    expect(estimate.percent, 50);
    expect(estimate.titleAr, 'امتلاء قاعدة البيانات');
    expect(estimate.captionAr, contains('الفعلية'));
  });

  test('function response maps used bytes and quota into a snapshot', () {
    final usage = DatabaseUsageSnapshot.fromFunctionResponse({
      'ok': true,
      'data': {
        'used_bytes': 1048576,
        'quota_bytes': 524288000,
        'percent': 0,
      },
    });
    expect(usage.usedBytes, 1048576);
    expect(usage.quotaBytes, 524288000);
    expect(usage.percent, 0);
  });
}
