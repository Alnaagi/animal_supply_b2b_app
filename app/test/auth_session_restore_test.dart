import 'package:animal_supply_b2b/src/data/local/local_auth_session_store.dart';
import 'package:animal_supply_b2b/src/data/repositories/demo_data.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('demo login is restored after a new AuthController bootstrap', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalAuthSessionStore(prefs: prefs);
    final first = AuthController(sessionStore: store);
    await first.restoreSession();

    await first.login('admin', 'admin');
    expect(first.state.user?.id, demoAdmin.id);
    expect(first.state.user?.isDemo, isTrue);
    expect(await store.readDemoUser(), isNotNull);

    final restored = AuthController(sessionStore: store);
    await restored.restoreSession();

    expect(restored.state.bootstrapping, isFalse);
    expect(restored.state.user?.id, demoAdmin.id);
    expect(restored.state.user?.role, 'admin');
    expect(restored.state.user?.isDemo, isTrue);
  });

  test('demo admin rejects the former email password', () async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AuthController(
      sessionStore: LocalAuthSessionStore(prefs: prefs),
    );
    await controller.restoreSession();

    await controller.login('admin', 'Admin123!');
    expect(controller.state.user, isNull);
    expect(controller.state.error, isNotNull);
  });

  test('demo customer can sign in with a WhatsApp phone number', () async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AuthController(
      sessionStore: LocalAuthSessionStore(prefs: prefs),
    );
    await controller.restoreSession();

    await controller.login('0910000001', 'Customer123!');
    expect(controller.state.user?.id, demoCustomer.id);
    expect(controller.state.user?.role, 'customer');
  });

  test('demo logout clears the persisted identity', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalAuthSessionStore(prefs: prefs);
    final controller = AuthController(sessionStore: store);
    await controller.restoreSession();

    await controller.login('tripoli-pets', 'Customer123!');
    await store.saveLastRoute('/orders');
    await controller.logout();

    expect(controller.state.user, isNull);
    expect(await store.readDemoUser(), isNull);
    expect(await store.readLastRoute(), isNull);

    final restored = AuthController(sessionStore: store);
    await restored.restoreSession();
    expect(restored.state.user, isNull);
  });

  test('restoreSession keeps last route for the router to resume', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalAuthSessionStore(prefs: prefs);
    await store.saveDemoUser(demoStaff.copyWith(isDemo: true));
    await store.saveLastRoute('/admin/orders?order=order-1');

    final controller = AuthController(sessionStore: store);
    await controller.restoreSession();

    expect(controller.state.user?.role, 'staff');
    expect(controller.state.restoredRoute, '/admin/orders?order=order-1');
  });
}
