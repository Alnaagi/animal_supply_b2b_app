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
    expect(estimate.titleAr, 'امتلاء البيانات');
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
  });

  test('production path is a local cache estimate, not a database quota', () {
    final estimate = estimateDashboardFullness(
      demoOrOffline: false,
      productCount: 50,
      orderCount: 999,
    );

    expect(estimate.kind, DashboardFullnessKind.localCache);
    expect(estimate.isDemoEstimate, isFalse);
    expect(estimate.isOperationalDbQuota, isFalse);
    expect(estimate.titleAr, 'امتلاء الذاكرة المحلية');
    expect(estimate.captionAr, contains('ليس سعة قاعدة البيانات'));
    expect(estimate.percent, 25);
  });

  test('empty local cache stays at zero without looking like a live quota', () {
    final estimate = estimateDashboardFullness(
      demoOrOffline: false,
      productCount: 0,
    );
    expect(estimate.percent, 0);
    expect(estimate.isOperationalDbQuota, isFalse);
  });
}
