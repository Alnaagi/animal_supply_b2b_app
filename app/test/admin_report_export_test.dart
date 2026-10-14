import 'dart:convert';

import 'package:animal_supply_b2b/src/core/config/app_config.dart';
import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/export/admin_report_export.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_reports/admin_report_export_sheet.dart';
import 'package:animal_supply_b2b/src/features/admin_reports/admin_reports_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sample = AdminReportData(
    periodOrderCount: 2,
    deliveredOrderCount: 1,
    cancelledOrderCount: 1,
    salesTotal: 60,
    averageOrderValue: 60,
    outstandingBalance: 125,
    topCustomers: [
      AdminCustomerReportRow(
        customerId: 'customer-1',
        businessName: 'متجر طرابلس',
        orderCount: 1,
        salesTotal: 60,
      ),
    ],
    topProducts: [
      AdminProductReportRow(
        productId: 'feed',
        productName: 'علف',
        sku: 'SKU-feed',
        quantity: 3,
        salesTotal: 60,
      ),
    ],
    lowStockProducts: [
      AdminInventoryReportRow(
        productId: 'empty',
        productName: 'دواء',
        sku: 'SKU-empty',
        availableQuantity: 0,
      ),
    ],
    outstandingCustomers: [
      AdminBalanceReportRow(
        customerId: 'customer-1',
        businessName: 'متجر طرابلس',
        outstandingBalance: 125,
        creditLimit: 1000,
      ),
    ],
  );

  test('Excel export includes selected datasets only and labels demo data', () {
    final bytes = AdminReportCsvExport.build(
      const AdminReportExportRequest(
        report: sample,
        periodLabel: 'آخر 30 يوماً',
        datasets: {
          AdminReportExportDataset.sales,
          AdminReportExportDataset.customers,
        },
        demoData: true,
      ),
    );
    expect(bytes.take(3), AdminReportCsvExport.utf8Bom);
    final csv = utf8.decode(bytes.sublist(3));
    expect(csv, contains(AppConfig.shopName));
    expect(csv, contains('بيانات تجريبية'));
    expect(csv, contains('ملخص المبيعات'));
    expect(csv, contains('أفضل العملاء'));
    expect(csv, contains('متجر طرابلس'));
    expect(csv, contains('60.00'));
    expect(csv, isNot(contains('٦٠')));
    expect(csv, isNot(contains('تنبيه المخزون')));
    expect(csv, isNot(contains('أرصدة')));
  });

  test('HTML export is RTL Arabic with shop branding and selected sections',
      () {
    final html = AdminReportHtmlExport.build(
      const AdminReportExportRequest(
        report: sample,
        periodLabel: 'آخر 30 يوماً',
        datasets: {
          AdminReportExportDataset.sales,
          AdminReportExportDataset.customers,
        },
        demoData: true,
        shopName: 'مؤسسة النور للأعلاف',
      ),
    );
    expect(html, contains('lang="ar"'));
    expect(html, contains('dir="rtl"'));
    expect(html, contains('text-align: right'));
    expect(html, contains('مؤسسة النور للأعلاف'));
    expect(html, contains('ملخص المبيعات'));
    expect(html, contains('أفضل العملاء'));
    expect(html, contains('د.ل'));
    expect(html, contains('font-feature-settings: "locl" 0'));
    expect(html, contains('60.00'));
    expect(html, contains('30'));
    expect(html, isNot(contains('٦')));
    expect(html, isNot(contains('٠')));
    expect(html, isNot(contains('تنبيه المخزون')));
    expect(html, isNot(contains('أفضل المنتجات')));
  });

  test('report PDF helpers keep Western digits for counts and money', () {
    expect(reportCount(12), '12');
    expect(reportMoney(60), contains('60.00'));
    expect(reportMoney(60), contains('د.ل'));
    expect(reportCount(12), isNot(contains('١')));
    expect(reportMoney(60), isNot(contains('٦')));
  });

  test('PDF export embeds selected Arabic dataset titles', () async {
    final fontData = await rootBundle.load(
      'assets/fonts/NotoSansArabic-Variable.ttf',
    );
    final bytes = await AdminReportPdfExport.build(
      const AdminReportExportRequest(
        report: sample,
        periodLabel: 'اليوم',
        datasets: {AdminReportExportDataset.inventory},
        demoData: true,
        shopName: 'مؤسسة النور للأعلاف',
      ),
      arabicFont: pw.Font.ttf(fontData),
    );
    expect(bytes.length, greaterThan(100));
    expect(
      String.fromCharCodes(bytes.take(8)),
      startsWith('%PDF'),
    );
  });

  test('RTL visual table rows put the first Arabic column on the right', () {
    expect(
      rtlVisualRow(const ['العميل', 'طلبات مسلّمة', 'المبيعات']),
      ['المبيعات', 'طلبات مسلّمة', 'العميل'],
    );
  });

  testWidgets('reports screen hides manual balances and offers export',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const product = Product(
      id: 'feed',
      nameAr: 'علف',
      sku: 'SKU-feed',
      category: 'ماشية',
      animalType: 'ماشية',
      brand: 'اختبار',
      unitSize: 'كيس',
      basePrice: 20,
      stockQuantity: 50,
      availableQuantity: 5,
      minOrderQty: 1,
    );
    final catalog = CatalogRepository.demo(seed: [product]);
    final orders = OrdersRepository.demo(
      seed: [
        Order(
          id: 'delivered',
          customerId: 'customer-1',
          businessName: 'متجر طرابلس',
          status: OrderStatus.delivered,
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: product.id,
              productName: product.name,
              productSku: product.sku,
              unitSize: product.unitSize,
              packageLabel: product.effectivePackageSize,
              quantity: 3,
              unitPrice: 20,
              lineTotal: 60,
              product: product,
            ),
          ],
          subtotal: 60,
          total: 60,
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/admin/reports',
      routes: [
        GoRoute(
          path: '/admin/reports',
          builder: (context, state) => const AdminReportsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _AdminAuthController()),
          catalogRepositoryProvider.overrideWithValue(catalog),
          ordersRepositoryProvider.overrideWithValue(orders),
          adminRepositoryProvider.overrideWithValue(AdminRepository()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('التقارير التشغيلية'), findsOneWidget);
    expect(find.text('مبيعات الفترة'), findsOneWidget);
    expect(find.text('أرصدة مرجعية مسجلة'), findsNothing);
    expect(find.text('الأرصدة المسجلة يدوياً'), findsNothing);
    expect(find.text('لا توجد أرصدة يدوية مسجلة.'), findsNothing);
    expect(
        find.byKey(const Key('admin-reports-export-button')), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('تصدير'))),
      TextDirection.rtl,
    );

    await tester.tap(find.byKey(const Key('admin-reports-export-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-report-export-sheet')), findsOneWidget);
    expect(find.text('ملخص المبيعات'), findsOneWidget);
    expect(find.text('أفضل العملاء'), findsOneWidget);
    expect(find.text('أفضل المنتجات'), findsOneWidget);
    expect(find.text('تنبيه المخزون'), findsWidgets);
    expect(find.text('أرصدة مرجعية مسجلة'), findsNothing);
  });

  testWidgets('chooser exports only checked datasets as Excel', (tester) async {
    final saved = <String, List<int>>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AdminReportExportSheet(
              report: sample,
              periodLabel: 'آخر 7 أيام',
              fileSaver: ({
                required filename,
                required bytes,
                required mimeType,
              }) {
                saved[filename] = bytes;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('admin-report-export-products')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin-report-export-inventory')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin-report-export-excel')));
    await tester.pumpAndSettle();

    expect(saved.keys.single, endsWith('.csv'));
    final csv = utf8.decode(saved.values.single.sublist(3));
    expect(csv, contains('ملخص المبيعات'));
    expect(csv, contains('أفضل العملاء'));
    expect(csv, isNot(contains('أفضل المنتجات')));
    expect(csv, isNot(contains('تنبيه المخزون')));
  });

  testWidgets('report cards open RTL detail sheets with underlying rows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const product = Product(
      id: 'feed',
      nameAr: 'علف',
      sku: 'SKU-feed',
      category: 'ماشية',
      animalType: 'ماشية',
      brand: 'اختبار',
      unitSize: 'كيس',
      basePrice: 20,
      stockQuantity: 50,
      availableQuantity: 5,
      minOrderQty: 1,
    );
    final catalog = CatalogRepository.demo(seed: [product]);
    final orders = OrdersRepository.demo(
      seed: [
        Order(
          id: 'delivered',
          orderNumber: 'ORD-1001',
          customerId: 'customer-1',
          businessName: 'متجر طرابلس',
          status: OrderStatus.delivered,
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: product.id,
              productName: product.name,
              productSku: product.sku,
              unitSize: product.unitSize,
              packageLabel: product.effectivePackageSize,
              quantity: 3,
              unitPrice: 20,
              lineTotal: 60,
              product: product,
            ),
          ],
          subtotal: 60,
          total: 60,
        ),
        Order(
          id: 'cancelled',
          orderNumber: 'ORD-1002',
          customerId: 'customer-1',
          businessName: 'متجر طرابلس',
          status: OrderStatus.cancelled,
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: product.id,
              productName: product.name,
              productSku: product.sku,
              unitSize: product.unitSize,
              packageLabel: product.effectivePackageSize,
              quantity: 1,
              unitPrice: 20,
              lineTotal: 20,
              product: product,
            ),
          ],
          subtotal: 20,
          total: 20,
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/admin/reports',
      routes: [
        GoRoute(
          path: '/admin/reports',
          builder: (context, state) => const AdminReportsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _AdminAuthController()),
          catalogRepositoryProvider.overrideWithValue(catalog),
          ordersRepositoryProvider.overrideWithValue(orders),
          adminRepositoryProvider.overrideWithValue(AdminRepository()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin-report-kpi-sales')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-report-detail-sheet')), findsOneWidget);
    expect(
      Directionality.of(
        tester.element(find.byKey(const Key('admin-report-detail-sheet'))),
      ),
      TextDirection.rtl,
    );
    expect(find.textContaining('ORD-1001'), findsOneWidget);
    expect(find.textContaining('ORD-1002'), findsNothing);
    expect(find.text('المبيعات'), findsWidgets);
    await _dismissDetailSheet(tester);

    await tester.tap(find.byKey(const Key('admin-report-kpi-average')));
    await tester.pumpAndSettle();
    expect(
      find.text('يحسب المتوسط من المبيعات المسلّمة ÷ عدد الطلبات المسلّمة.'),
      findsOneWidget,
    );
    await _dismissDetailSheet(tester);

    await tester.tap(find.byKey(const Key('admin-report-kpi-cancelled')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ORD-1002'), findsOneWidget);
    expect(find.textContaining('ORD-1001'), findsNothing);
    await _dismissDetailSheet(tester);

    await tester.ensureVisible(
      find.byKey(const Key('admin-report-panel-customers')),
    );
    await tester.tap(find.byKey(const Key('admin-report-panel-customers')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-report-detail-sheet')), findsOneWidget);
    expect(find.text('العملاء حسب المبيعات المسلّمة في آخر 30 يوماً'),
        findsOneWidget);
    await _dismissDetailSheet(tester);

    await tester.ensureVisible(
      find.byKey(const Key('admin-report-panel-products')),
    );
    await tester.tap(find.byKey(const Key('admin-report-panel-products')));
    await tester.pumpAndSettle();
    expect(find.text('المنتجات حسب الكمية المباعة في آخر 30 يوماً'),
        findsOneWidget);
    expect(find.textContaining('SKU-feed'), findsWidgets);
    await _dismissDetailSheet(tester);

    await tester.ensureVisible(
      find.byKey(const Key('admin-report-panel-inventory')),
    );
    await tester.tap(find.byKey(const Key('admin-report-panel-inventory')));
    await tester.pumpAndSettle();
    expect(
        find.text('منتجات بكمية منخفضة أو غير متوفرة حالياً'), findsOneWidget);
  });
}

Future<void> _dismissDetailSheet(WidgetTester tester) async {
  Navigator.of(
    tester.element(find.byKey(const Key('admin-report-detail-sheet'))),
  ).pop();
  await tester.pumpAndSettle();
}

class _AdminAuthController extends AuthController {
  _AdminAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'admin-reports-export-test',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}
