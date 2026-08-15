import 'package:animal_supply_b2b/src/data/local/local_auth_session_store.dart';
import 'package:animal_supply_b2b/src/data/repositories/demo_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('demo identity persists by id and ignores unknown users', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalAuthSessionStore(prefs: prefs);

    expect(await store.readDemoUser(), isNull);
    expect(
      await store.saveDemoUser(demoAdmin),
      isFalse,
    );

    final saved = await store.saveDemoUser(demoAdmin.copyWith(isDemo: true));
    expect(saved, isTrue);

    final restored = await store.readDemoUser();
    expect(restored?.id, demoAdmin.id);
    expect(restored?.role, 'admin');
    expect(restored?.isDemo, isTrue);

    await store.clearDemoUser();
    expect(await store.readDemoUser(), isNull);
  });

  test('last route survives reload and is cleared on logout-style wipe',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalAuthSessionStore(prefs: prefs);

    expect(await store.saveLastRoute('/admin/settings'), isTrue);
    expect(await store.readLastRoute(), '/admin/settings');

    await store.clear();
    expect(await store.readDemoUser(), isNull);
    expect(await store.readLastRoute(), isNull);
  });
}
