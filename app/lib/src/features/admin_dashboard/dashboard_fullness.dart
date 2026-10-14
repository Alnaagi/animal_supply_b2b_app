import '../../data/models/database_usage.dart';

/// Fullness shown on the admin dashboard circular widget.
enum DashboardFullnessKind {
  demoCatalog,
  localCacheFallback,
  operationalDb,
}

class DashboardFullnessEstimate {
  const DashboardFullnessEstimate({
    required this.percent,
    required this.kind,
    required this.titleAr,
    required this.captionAr,
  });

  final int percent;
  final DashboardFullnessKind kind;
  final String titleAr;
  final String captionAr;

  bool get isDemoEstimate => kind == DashboardFullnessKind.demoCatalog;
  bool get isFallbackEstimate =>
      kind == DashboardFullnessKind.localCacheFallback;
  bool get isOperationalDbQuota => kind == DashboardFullnessKind.operationalDb;
}

const databaseFullnessTitleAr = 'امتلاء قاعدة البيانات';

/// Demo catalog+orders vs a labelled demo cap. Production uses live
/// Postgres size from the admin Edge Function, or a labelled local fallback.
DashboardFullnessEstimate estimateDashboardFullness({
  required bool demoOrOffline,
  required int productCount,
  int orderCount = 0,
  int demoProductCap = 80,
  int demoOrderCap = 20,
  int localCacheProductCap = 200,
}) {
  final safeProducts = productCount < 0 ? 0 : productCount;
  final safeOrders = orderCount < 0 ? 0 : orderCount;

  if (demoOrOffline) {
    final productRatio =
        (safeProducts / (demoProductCap <= 0 ? 1 : demoProductCap))
            .clamp(0.0, 1.0);
    final orderRatio =
        (safeOrders / (demoOrderCap <= 0 ? 1 : demoOrderCap)).clamp(0.0, 1.0);
    final percent =
        ((productRatio * 0.65 + orderRatio * 0.35) * 100).round().clamp(0, 100);
    return DashboardFullnessEstimate(
      percent: percent,
      kind: DashboardFullnessKind.demoCatalog,
      titleAr: databaseFullnessTitleAr,
      captionAr: 'تقدير تجريبي من الكتالوج والطلبات المحلية — غير تشغيلي',
    );
  }

  return localCacheFallbackFullness(
    productCount: safeProducts,
    localCacheProductCap: localCacheProductCap,
  );
}

DashboardFullnessEstimate localCacheFallbackFullness({
  required int productCount,
  int localCacheProductCap = 200,
}) {
  final cap = localCacheProductCap <= 0 ? 1 : localCacheProductCap;
  final percent = ((productCount.clamp(0, 1 << 30) / cap).clamp(0.0, 1.0) * 100)
      .round()
      .clamp(0, 100);
  return DashboardFullnessEstimate(
    percent: percent,
    kind: DashboardFullnessKind.localCacheFallback,
    titleAr: databaseFullnessTitleAr,
    captionAr: 'تعذر قراءة سعة قاعدة البيانات — تقدير محلي من ذاكرة الجهاز',
  );
}

DashboardFullnessEstimate operationalDatabaseFullness(
  DatabaseUsageSnapshot usage,
) {
  return DashboardFullnessEstimate(
    percent: usage.percent.clamp(0, 100),
    kind: DashboardFullnessKind.operationalDb,
    titleAr: databaseFullnessTitleAr,
    captionAr: 'نسبة الامتلاء الفعلية من قاعدة البيانات على الخادم',
  );
}
