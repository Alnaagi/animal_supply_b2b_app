import 'package:animal_supply_b2b/src/features/admin_dashboard/dashboard_widget_visibility.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('missing prefs keep every dashboard widget visible', () {
    expect(
      DashboardWidgetVisibility.decode(null).isVisible(
        DashboardWidgetId.customers,
      ),
      isTrue,
    );
    expect(
      DashboardWidgetVisibility.decode('').isVisible(
        DashboardWidgetId.pendingOrdersPanel,
      ),
      isTrue,
    );
    expect(
      DashboardWidgetVisibility.decode('{not-json}').isVisible(
        DashboardWidgetId.dataFullness,
      ),
      isTrue,
    );
  });

  test('unknown keys are ignored and new widgets default to visible', () {
    final visibility = DashboardWidgetVisibility.decode(
      '{"customers":false,"legacy_widget":false}',
    );
    expect(visibility.isVisible(DashboardWidgetId.customers), isFalse);
    expect(visibility.isVisible(DashboardWidgetId.lowStockPanel), isTrue);
    expect(visibility.isVisible(DashboardWidgetId.dataFullness), isTrue);
  });

  test('visibility round-trips through SharedPreferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = DashboardWidgetPrefs(prefs: prefs);
    final hidden = DashboardWidgetVisibility.allVisible
        .withVisible(DashboardWidgetId.customers, false)
        .withVisible(DashboardWidgetId.pendingOrdersPanel, false);

    expect(await store.save(hidden), isTrue);
    expect(prefs.getString(DashboardWidgetPrefs.storageKey), isNotEmpty);

    final loaded = await store.load();
    expect(loaded.isVisible(DashboardWidgetId.customers), isFalse);
    expect(loaded.isVisible(DashboardWidgetId.pendingOrdersPanel), isFalse);
    expect(loaded.isVisible(DashboardWidgetId.monthSales), isTrue);
    expect(loaded.isVisible(DashboardWidgetId.dataFullness), isTrue);
  });
}
