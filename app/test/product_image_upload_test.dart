import 'dart:typed_data';

import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/product_images_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_products/admin_products_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('valid PNG uploads to a randomized owner path and returns HTTPS',
      () async {
    final storage = _FakeStorage();
    final repository = ProductImagesRepository(
      picker: _FakePicker(_png('photo.png')),
      storage: storage,
      randomId: () => '11111111-2222-4333-8444-555555555555',
    );

    final result = await repository.pickAndUpload();

    expect(result, isNotNull);
    expect(
      storage.path,
      'products/${storage.currentUserId}/11111111-2222-4333-8444-555555555555.png',
    );
    expect(storage.contentType, 'image/png');
    expect(storage.bytes, _png('ignored').bytes);
    expect(result?.publicUrl, startsWith('https://storage.example/'));
  });

  test('banner uploads use the banners storage folder', () async {
    final storage = _FakeStorage();
    final repository = ProductImagesRepository(
      picker: _FakePicker(_png('banner.png')),
      storage: storage,
      randomId: () => 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    );

    final result = await repository.pickAndUploadBanner();

    expect(result, isNotNull);
    expect(
      storage.path,
      'banners/${storage.currentUserId}/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee.png',
    );
    expect(result?.publicUrl, startsWith('https://storage.example/'));
  });

  test('unsupported upload folders are rejected before picking', () async {
    final picker = _FakePicker(_png('photo.png'));
    final repository = ProductImagesRepository(
      picker: picker,
      storage: _FakeStorage(),
    );

    await expectLater(
      repository.pickAndUpload(folder: 'avatars'),
      throwsA(
        isA<ProductImageUploadException>().having(
          (error) => error.code,
          'code',
          'INVALID_FOLDER',
        ),
      ),
    );
    expect(picker.calls, 0);
  });

  test('renamed or unsupported files are rejected before upload', () async {
    final storage = _FakeStorage();
    final repository = ProductImagesRepository(
      picker: _FakePicker(
        PickedProductImage(
          fileName: 'not-really.png',
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      ),
      storage: storage,
    );

    await expectLater(
      repository.pickAndUpload(),
      throwsA(
        isA<ProductImageUploadException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_IMAGE',
        ),
      ),
    );
    expect(storage.path, isNull);
  });

  test('files above 5 MiB are rejected before upload', () async {
    final storage = _FakeStorage();
    final bytes = Uint8List(ProductImagesRepository.maxBytes + 1)
      ..setAll(0, _png('large.png').bytes);
    final repository = ProductImagesRepository(
      picker: _FakePicker(
        PickedProductImage(fileName: 'large.png', bytes: bytes),
      ),
      storage: storage,
    );

    await expectLater(
      repository.pickAndUpload(),
      throwsA(
        isA<ProductImageUploadException>().having(
          (error) => error.code,
          'code',
          'FILE_TOO_LARGE',
        ),
      ),
    );
    expect(storage.path, isNull);
  });

  test('demo mode fails closed without opening a fake picker', () async {
    final picker = _FakePicker(_png('photo.png'));
    final repository = ProductImagesRepository(
      picker: picker,
      resolveConfiguredStorage: false,
    );

    expect(repository.canUpload, isFalse);
    await expectLater(
      repository.pickAndUpload(),
      throwsA(
        isA<ProductImageUploadException>().having(
          (error) => error.code,
          'code',
          'BACKEND_REQUIRED',
        ),
      ),
    );
    expect(picker.calls, 0);
  });

  test('an unsafe public URL is rejected and the object is cleaned up',
      () async {
    final storage = _FakeStorage(publicUrlValue: 'http://unsafe.test/image');
    final repository = ProductImagesRepository(
      picker: _FakePicker(_png('photo.png')),
      storage: storage,
    );

    await expectLater(
      repository.pickAndUpload(),
      throwsA(
        isA<ProductImageUploadException>().having(
          (error) => error.code,
          'code',
          'INVALID_PUBLIC_URL',
        ),
      ),
    );
    expect(storage.removed, storage.path);
  });

  testWidgets(
      'admin dialog exposes the simplified Arabic product fields and '
      'separate inventory visibility controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/admin/products',
      routes: [
        GoRoute(
          path: '/admin/products',
          builder: (context, state) => const AdminProductsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _AdminAuthController(),
          ),
          catalogRepositoryProvider.overrideWithValue(
            CatalogRepository.demo(seed: const []),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('منتج جديد'));
    await tester.pumpAndSettle();

    expect(find.text('منتج جديد'), findsWidgets);
    expect(
      find.byKey(const ValueKey('product-form-scroll-hint')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('product-form-scrollbar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('product-name-field')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('product-category-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('product-company-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-price-field')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('product-retail-price-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('product-bulk-minimum-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('product-units-per-box-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('product-track-stock-switch')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('product-stock-field')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('product-show-stock-quantity-switch'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('product-visible-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('product-hide-when-out-of-stock-switch'),
      ),
      findsOneWidget,
    );
    expect(find.text('سعر الجملة (د.ل)'), findsOneWidget);
    expect(find.text('سعر بيع الوحدة المقترح (د.ل)'), findsOneWidget);
    expect(find.text('الحد الأدنى لطلب الجملة'), findsOneWidget);
    expect(find.text('الكمية في الصندوق (اختياري)'), findsOneWidget);
    expect(find.text('كمية المخزون الداخلية (مطلوبة)'), findsOneWidget);
    expect(find.text('رابط صورة HTTPS'), findsNothing);
    expect(find.text('اختيار ورفع صورة'), findsNothing);
    expect(find.text('الوصف'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('product-track-stock-switch')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('product-track-stock-switch')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('product-stock-field')), findsOneWidget);
    final quantityVisibility = tester.widget<SwitchListTile>(
      find.byKey(
        const ValueKey('product-show-stock-quantity-switch'),
      ),
    );
    expect(quantityVisibility.onChanged, isNull);
    expect(
      find.byKey(
        const ValueKey('product-hide-when-out-of-stock-switch'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('product-visible-switch')),
      findsOneWidget,
    );
  });
}

PickedProductImage _png(String name) => PickedProductImage(
      fileName: name,
      bytes: Uint8List.fromList(
        const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      ),
    );

class _FakePicker implements ProductImagePicker {
  _FakePicker(this.result);

  final PickedProductImage? result;
  int calls = 0;

  @override
  Future<PickedProductImage?> pick() async {
    calls++;
    return result;
  }
}

class _FakeStorage implements ProductImageStorageGateway {
  _FakeStorage({
    this.publicUrlValue = 'https://storage.example/product.png',
  });

  final String publicUrlValue;
  @override
  final String currentUserId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  String? path;
  String? contentType;
  Uint8List? bytes;
  String? removed;

  @override
  String publicUrl(String path) => publicUrlValue;

  @override
  Future<void> remove(String path) async {
    removed = path;
  }

  @override
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    this.path = path;
    this.bytes = bytes;
    this.contentType = contentType;
  }
}

class _AdminAuthController extends AuthController {
  _AdminAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'admin-product-test',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}
