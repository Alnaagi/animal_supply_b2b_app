import 'dart:async';
import 'dart:typed_data';

import 'package:animal_supply_b2b/src/core/widgets/banner_image_crop_dialog.dart';
import 'package:animal_supply_b2b/src/core/widgets/circular_upload_progress.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/product_images_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_banners/admin_banners_screen.dart';
import 'package:animal_supply_b2b/src/features/admin_products/admin_products_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

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

  test('category icon uploads use the category-icons storage folder', () async {
    final storage = _FakeStorage();
    final repository = ProductImagesRepository(
      picker: _FakePicker(_png('category.png')),
      storage: storage,
      randomId: () => 'cccccccc-dddd-4eee-8fff-000000000000',
    );

    final result = await repository.pickAndUploadCategoryIcon();

    expect(result, isNotNull);
    expect(
      storage.path,
      'category-icons/${storage.currentUserId}/cccccccc-dddd-4eee-8fff-000000000000.png',
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

  test('storage 403 is mapped to an Arabic permission reason', () {
    final mapped = mapProductImageUploadError(
      const StorageException(
        'new row violates row-level security policy',
        statusCode: '403',
        error: 'Unauthorized',
      ),
      folder: ProductImagesRepository.productsFolder,
    );
    expect(mapped.code, 'UPLOAD_FORBIDDEN');
    expect(mapped.message, contains('صلاحية رفع صور المنتجات'));
  });

  test('missing bucket 404 is mapped to an Arabic storage reason', () {
    final mapped = mapProductImageUploadError(
      const StorageException('Bucket not found', statusCode: '404'),
      folder: ProductImagesRepository.productsFolder,
    );
    expect(mapped.code, 'BUCKET_MISSING');
    expect(mapped.message, contains('product-images'));
  });

  test('invalid mime 400 includes the storage detail in Arabic wrapping', () {
    final mapped = mapProductImageUploadError(
      const StorageException(
        'mime type image/heic is not supported',
        statusCode: '400',
        error: 'InvalidRequest',
      ),
      folder: ProductImagesRepository.productsFolder,
    );
    expect(mapped.code, 'UNSUPPORTED_IMAGE');
    expect(mapped.message, contains('JPEG أو PNG أو WebP'));
    expect(mapped.message, contains('image/heic'));
  });

  test('network failures surface an Arabic CORS/connection reason', () {
    final mapped = mapProductImageUploadError(
      Exception('ClientException: Failed to fetch'),
      folder: ProductImagesRepository.productsFolder,
    );
    expect(mapped.code, 'UPLOAD_NETWORK');
    expect(mapped.message, contains('CORS'));
    expect(mapped.message, isNot(contains('Exception:')));
  });

  test('revoked browser blob URLs map to Arabic without English dump', () {
    final mapped = mapProductImageUploadError(
      Exception('Could not load Blob from its URL. Has it been revoked?'),
      folder: ProductImagesRepository.productsFolder,
    );
    expect(mapped.code, 'UPLOAD_BROWSER_FILE');
    expect(mapped.message, contains('تعذر قراءة ملف الصورة في المتصفح'));
    expect(mapped.message, isNot(contains('Exception:')));
    expect(mapped.message, isNot(contains('revoked')));
  });

  test('upload progress is indeterminate then 100 percent', () async {
    final storage = _FakeStorage();
    final progress = <double?>[];
    final repository = ProductImagesRepository(
      picker: _FakePicker(_png('photo.png')),
      storage: storage,
      randomId: () => '11111111-2222-4333-8444-555555555555',
    );

    await repository.pickAndUpload(onProgress: progress.add);

    expect(progress.first, 0);
    expect(progress.contains(null), isTrue);
    expect(progress.last, 1);
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
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('product-track-stock-switch')),
          )
          .value,
      isFalse,
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
      findsNothing,
    );
    expect(find.text('سعر الجملة (د.ل)'), findsOneWidget);
    expect(find.text('سعر بيع الوحدة المقترح (د.ل)'), findsOneWidget);
    expect(find.text('الحد الأدنى لطلب الجملة'), findsOneWidget);
    expect(find.text('الكمية في الصندوق (اختياري)'), findsOneWidget);
    expect(find.text('كمية المخزون الداخلية (مطلوبة)'), findsOneWidget);
    expect(find.text('صورة المنتج'), findsOneWidget);
    expect(find.text('رفع صورة'), findsOneWidget);
    expect(find.text('أو رابط https'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('product-image-upload-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('product-image-url-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('product-image-preview')),
      findsOneWidget,
    );
    expect(find.text('رابط صورة HTTPS'), findsNothing);
    expect(find.text('اختيار ورفع صورة'), findsNothing);
    expect(find.text('الوصف'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('product-image-url-field')),
      'http://insecure.example/image.png',
    );
    await tester.tap(find.text('حفظ المنتج'));
    await tester.pumpAndSettle();
    expect(
      find.text('استخدم رابط https صالحاً ومن دون بيانات دخول، أو ارفع صورة.'),
      findsOneWidget,
    );

    final trackSwitch =
        find.byKey(const ValueKey('product-track-stock-switch'));
    await tester.ensureVisible(trackSwitch);
    await tester.pumpAndSettle();
    await tester.tap(trackSwitch);
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
    expect(quantityVisibility.onChanged, isNotNull);
    expect(
      find.byKey(
        const ValueKey('product-hide-when-out-of-stock-switch'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('product-visible-switch')),
      findsOneWidget,
    );
  });

  testWidgets('new product upload shows a percent circle then the public URL',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _GatedStorage();
    final repository = ProductImagesRepository(
      picker: _FakePicker(_png('photo.png')),
      storage: storage,
      randomId: () => '11111111-2222-4333-8444-555555555555',
    );

    await _pumpProductForm(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('product-image-upload-button')));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('product-image-upload-progress')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    storage.gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('product-image-upload-progress')),
      findsNothing,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('product-image-url-field')),
          )
          .controller
          ?.text,
      startsWith('https://storage.example/'),
    );
  });

  testWidgets('new product upload surfaces the Arabic storage failure reason',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = ProductImagesRepository(
      picker: _FakePicker(_png('photo.png')),
      storage: _FakeStorage(
        uploadError: const StorageException(
          'new row violates row-level security policy',
          statusCode: '403',
        ),
      ),
    );

    await _pumpProductForm(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('product-image-upload-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('صلاحية رفع صور المنتجات'), findsOneWidget);
    expect(
      find.textContaining('تعذر رفع الصورة. تحقق من الاتصال'),
      findsNothing,
    );
    expect(find.textContaining('Exception:'), findsNothing);
  });

  testWidgets('banner upload opens crop editor then surfaces Arabic failure',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = ProductImagesRepository(
      picker: _FakePicker(_validPng('banner.png', width: 80, height: 32)),
      storage: _FakeStorage(
        uploadError: const StorageException(
          'new row violates row-level security policy',
          statusCode: '403',
        ),
      ),
    );

    final router = GoRouter(
      initialLocation: '/admin/banners',
      routes: [
        GoRoute(
          path: '/admin/banners',
          builder: (context, state) => const AdminBannersScreen(),
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
          productImagesRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('بانر جديد'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('banner-image-upload-button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('banner-image-crop-dialog')), findsOneWidget);
    expect(find.text('قص الصورة'), findsOneWidget);
    expect(find.byKey(const ValueKey('banner-crop-fit')), findsOneWidget);
    expect(find.byKey(const ValueKey('banner-crop-save')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('banner-crop-save')));
    await tester.pump();
    // Allow crop export + upload to settle.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.textContaining('صلاحية رفع صور البانرات'), findsOneWidget);
    expect(
      find.textContaining('تعذر رفع الصورة. تحقق من الاتصال'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('banner-image-preview')), findsOneWidget);
  });

  testWidgets('banner upload shows circular percent progress after crop',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _GatedStorage();
    final repository = ProductImagesRepository(
      picker: _FakePicker(_validPng('banner.png', width: 96, height: 40)),
      storage: storage,
      randomId: () => 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );

    final router = GoRouter(
      initialLocation: '/admin/banners',
      routes: [
        GoRoute(
          path: '/admin/banners',
          builder: (context, state) => const AdminBannersScreen(),
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
          productImagesRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('بانر جديد'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('banner-image-upload-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('banner-crop-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byKey(const ValueKey('banner-image-upload-progress')),
      findsOneWidget,
    );
    expect(find.byType(CircularUploadProgress), findsOneWidget);
    expect(find.textContaining('جارٍ الرفع'), findsOneWidget);

    storage.gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('banner-image-upload-progress')),
      findsNothing,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('banner-image-url-field')),
          )
          .controller
          ?.text,
      startsWith('https://storage.example/'),
    );
  });

  testWidgets('banner crop dialog exposes Arabic fit and save actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BannerImageCropDialog(
          imageBytes: _validPng('source.png', width: 64, height: 28).bytes,
          sourceFileName: 'source.png',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('قص الصورة'), findsOneWidget);
    expect(find.text('ملاءمة'), findsOneWidget);
    expect(find.text('حفظ القص'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);
    expect(kBannerCropAspectRatio, closeTo(1600 / 620, 0.0001));
  });
}

PickedProductImage _png(String name) => PickedProductImage(
      fileName: name,
      bytes: Uint8List.fromList(
        const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      ),
    );

PickedProductImage _validPng(
  String name, {
  int width = 32,
  int height = 16,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(18, 120, 96));
  return PickedProductImage(
    fileName: name,
    bytes: Uint8List.fromList(img.encodePng(image)),
  );
}

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
    this.uploadError,
  });

  final String publicUrlValue;
  final Object? uploadError;
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
    ProductImageUploadProgress? onProgress,
  }) async {
    onProgress?.call(null);
    if (uploadError != null) {
      throw uploadError!;
    }
    this.path = path;
    this.bytes = bytes;
    this.contentType = contentType;
    onProgress?.call(1);
  }
}

class _GatedStorage extends _FakeStorage {
  final gate = Completer<void>();

  @override
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
    ProductImageUploadProgress? onProgress,
  }) async {
    onProgress?.call(null);
    await gate.future;
    this.path = path;
    this.bytes = bytes;
    this.contentType = contentType;
    onProgress?.call(1);
  }
}

Future<void> _pumpProductForm(
  WidgetTester tester, {
  required ProductImagesRepository repository,
}) async {
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
        productImagesRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('منتج جديد'));
  await tester.pumpAndSettle();
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
