/// Local/demo fullness estimate for the admin dashboard.
///
/// This is never a live production database quota. There is no client-side
/// quota API, and the Flutter app must not invent one with a service role.
enum DashboardFullnessKind {
  demoCatalog,
  localCache,
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
  bool get isOperationalDbQuota => false;
}

/// Demo catalog+orders vs a labelled demo cap. Production uses the local
/// catalog cache vs the offline snapshot limit — not database capacity.
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
    final percent = ((productRatio * 0.65 + orderRatio * 0.35) * 100)
        .round()
        .clamp(0, 100);
    return DashboardFullnessEstimate(
      percent: percent,
      kind: DashboardFullnessKind.demoCatalog,
      titleAr: 'امتلاء البيانات',
      captionAr:
          'تقدير تجريبي من الكتالوج والطلبات المحلية — غير تشغيلي',
    );
  }

  final cap = localCacheProductCap <= 0 ? 1 : localCacheProductCap;
  final percent =
      ((safeProducts / cap).clamp(0.0, 1.0) * 100).round().clamp(0, 100);
  return DashboardFullnessEstimate(
    percent: percent,
    kind: DashboardFullnessKind.localCache,
    titleAr: 'امتلاء الذاكرة المحلية',
    captionAr: 'تقدير من ذاكرة الكتالوج على الجهاز — ليس سعة قاعدة البيانات',
  );
}
