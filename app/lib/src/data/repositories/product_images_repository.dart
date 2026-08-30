import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/files/browser_product_image_picker.dart';
import '../remote/supabase_clients.dart';

final productImagesRepositoryProvider = Provider<ProductImagesRepository>(
  (ref) => ProductImagesRepository(),
);

class ProductImageUploadException implements Exception {
  const ProductImageUploadException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => message;
}

class PickedProductImage {
  const PickedProductImage({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

class ProductImageUploadResult {
  const ProductImageUploadResult({
    required this.publicUrl,
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
  });

  final String publicUrl;
  final String storagePath;
  final String contentType;
  final int sizeBytes;
}

abstract interface class ProductImagePicker {
  Future<PickedProductImage?> pick();
}

typedef ProductImageUploadProgress = void Function(double? fraction);

abstract interface class ProductImageStorageGateway {
  String? get currentUserId;

  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
    ProductImageUploadProgress? onProgress,
  });

  String publicUrl(String path);

  Future<void> remove(String path);
}

class ProductImagesRepository {
  ProductImagesRepository({
    ProductImagePicker? picker,
    ProductImageStorageGateway? storage,
    String Function()? randomId,
    bool resolveConfiguredStorage = true,
  })  : _picker = picker ?? const FileSelectorProductImagePicker(),
        _storage =
            storage ?? (resolveConfiguredStorage ? _configuredStorage() : null),
        _randomId = randomId ?? const Uuid().v4;

  static const bucketName = 'product-images';
  static const productsFolder = 'products';
  static const bannersFolder = 'banners';
  static const logosFolder = 'logos';
  static const categoryIconsFolder = 'category-icons';
  static const maxBytes = 5 * 1024 * 1024;

  final ProductImagePicker _picker;
  final ProductImageStorageGateway? _storage;
  final String Function() _randomId;

  bool get canUpload =>
      _storage != null && (_storage.currentUserId?.trim().isNotEmpty ?? false);

  Future<PickedProductImage?> pick() => _picker.pick();

  Future<ProductImageUploadResult?> pickAndUpload({
    String folder = productsFolder,
    ProductImageUploadProgress? onProgress,
  }) =>
      _pickAndUpload(folder: folder, onProgress: onProgress);

  Future<ProductImageUploadResult?> pickAndUploadBanner({
    ProductImageUploadProgress? onProgress,
  }) =>
      _pickAndUpload(folder: bannersFolder, onProgress: onProgress);

  Future<ProductImageUploadResult?> pickAndUploadLogo({
    ProductImageUploadProgress? onProgress,
  }) =>
      _pickAndUpload(folder: logosFolder, onProgress: onProgress);

  Future<ProductImageUploadResult?> pickAndUploadCategoryIcon({
    ProductImageUploadProgress? onProgress,
  }) =>
      _pickAndUpload(folder: categoryIconsFolder, onProgress: onProgress);

  Future<ProductImageUploadResult> uploadPicked(
    PickedProductImage picked, {
    String folder = productsFolder,
    ProductImageUploadProgress? onProgress,
  }) =>
      _uploadPicked(picked, folder: folder, onProgress: onProgress);

  /// Extracts `banners/{uid}/{file}` from a public product-images URL.
  /// Returns null for external/CDN URLs so unrelated assets are never deleted.
  static String? bannerStoragePathFromPublicUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https') return null;
    const marker = '/object/public/$bucketName/';
    final full = uri.path;
    final markerIndex = full.indexOf(marker);
    if (markerIndex < 0) return null;
    final path =
        Uri.decodeComponent(full.substring(markerIndex + marker.length));
    if (!path.startsWith('$bannersFolder/')) return null;
    final segments = path.split('/');
    if (segments.length != 3) return null;
    if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(segments[1])) return null;
    if (!RegExp(r'^[A-Za-z0-9-]+\.(jpg|jpeg|png|webp)$')
        .hasMatch(segments[2])) {
      return null;
    }
    return path;
  }

  Future<void> removeByStoragePath(String path) async {
    final storage = _storage;
    if (storage == null) {
      throw const ProductImageUploadException(
        code: 'BACKEND_REQUIRED',
        message: 'حذف صورة التخزين يحتاج ربط Supabase الإنتاجي.',
      );
    }
    final normalized = path.trim();
    if (bannerStoragePathFromPublicUrl(
          storage.publicUrl(normalized),
        ) !=
        normalized) {
      // Only allow deleting paths that match the banners object pattern.
      final segments = normalized.split('/');
      if (segments.length != 3 ||
          segments[0] != bannersFolder ||
          !RegExp(r'^[0-9a-f-]{36}$').hasMatch(segments[1]) ||
          !RegExp(r'^[A-Za-z0-9-]+\.(jpg|jpeg|png|webp)$')
              .hasMatch(segments[2])) {
        throw const ProductImageUploadException(
          code: 'INVALID_PATH',
          message: 'مسار صورة البانر غير صالح للحذف.',
        );
      }
    }
    await storage.remove(normalized);
  }

  Future<ProductImageUploadResult?> _pickAndUpload({
    required String folder,
    ProductImageUploadProgress? onProgress,
  }) async {
    _assertCanUpload(folder);
    final picked = await _picker.pick();
    if (picked == null) return null;
    return _uploadPicked(picked, folder: folder, onProgress: onProgress);
  }

  void _assertCanUpload(String folder) {
    final storage = _storage;
    final ownerId = storage?.currentUserId?.trim();
    if (storage == null || ownerId == null || ownerId.isEmpty) {
      throw const ProductImageUploadException(
        code: 'BACKEND_REQUIRED',
        message:
            'رفع الصور يحتاج ربط Supabase الإنتاجي وتسجيل دخول إداري. استخدم رابط HTTPS يدوياً حالياً.',
      );
    }
    if (folder != productsFolder &&
        folder != bannersFolder &&
        folder != logosFolder &&
        folder != categoryIconsFolder) {
      throw const ProductImageUploadException(
        code: 'INVALID_FOLDER',
        message: 'مسار رفع الصورة غير مدعوم.',
      );
    }
  }

  Future<ProductImageUploadResult> _uploadPicked(
    PickedProductImage picked, {
    required String folder,
    ProductImageUploadProgress? onProgress,
  }) async {
    _assertCanUpload(folder);
    final storage = _storage!;
    final ownerId = storage.currentUserId!.trim();
    final type = _validatedType(picked.fileName, picked.bytes);
    final randomId = _randomId().replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');
    if (randomId.isEmpty) {
      throw const ProductImageUploadException(
        code: 'INVALID_RANDOM_PATH',
        message: 'تعذر إنشاء مسار آمن للصورة. حاول من جديد.',
      );
    }
    final path = '$folder/$ownerId/$randomId.${type.extension}';
    onProgress?.call(0);

    try {
      await storage.upload(
        path: path,
        bytes: picked.bytes,
        contentType: type.contentType,
        onProgress: onProgress,
      );
      onProgress?.call(1);
      final url = storage.publicUrl(path);
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        try {
          await storage.remove(path);
        } catch (_) {}
        throw const ProductImageUploadException(
          code: 'INVALID_PUBLIC_URL',
          message: 'تم رفض رابط التخزين لأنه ليس رابط HTTPS عاماً وآمناً.',
        );
      }
      return ProductImageUploadResult(
        publicUrl: uri.toString(),
        storagePath: path,
        contentType: type.contentType,
        sizeBytes: picked.bytes.length,
      );
    } on ProductImageUploadException {
      rethrow;
    } catch (error) {
      throw mapUploadError(error, folder: folder);
    }
  }

  static ProductImageUploadException mapUploadError(
    Object error, {
    required String folder,
  }) {
    return mapProductImageUploadError(error, folder: folder);
  }

  static _ValidatedImageType _validatedType(
    String fileName,
    Uint8List bytes,
  ) {
    if (bytes.isEmpty) {
      throw const ProductImageUploadException(
        code: 'EMPTY_FILE',
        message: 'ملف الصورة فارغ.',
      );
    }
    if (bytes.length > maxBytes) {
      throw const ProductImageUploadException(
        code: 'FILE_TOO_LARGE',
        message: 'حجم الصورة أكبر من 5 MiB.',
      );
    }

    final extension =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    if (_isPng(bytes) && extension == 'png') {
      return const _ValidatedImageType('png', 'image/png');
    }
    if (_isJpeg(bytes) && (extension == 'jpg' || extension == 'jpeg')) {
      return const _ValidatedImageType('jpg', 'image/jpeg');
    }
    if (_isWebp(bytes) && extension == 'webp') {
      return const _ValidatedImageType('webp', 'image/webp');
    }
    throw const ProductImageUploadException(
      code: 'UNSUPPORTED_IMAGE',
      message: 'اختر صورة JPEG أو PNG أو WebP حقيقية فقط.',
    );
  }

  static bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;

  static bool _isPng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;

  static bool _isWebp(Uint8List bytes) =>
      bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;

  static ProductImageStorageGateway? _configuredStorage() {
    final client = supabaseClient;
    return client == null ? null : SupabaseProductImageStorageGateway(client);
  }
}

ProductImageUploadException mapProductImageUploadError(
  Object error, {
  required String folder,
}) {
  if (error is ProductImageUploadException) return error;
  if (error is BrowserPickedImageException) {
    return ProductImageUploadException(
      code: error.code,
      message: error.message,
    );
  }

  final forbiddenMessage = switch (folder) {
    ProductImagesRepository.bannersFolder =>
      'ليس للحساب صلاحية رفع صور البانرات. تحقق من دور المدير وسياسات التخزين.',
    ProductImagesRepository.logosFolder =>
      'ليس للحساب صلاحية رفع شعار المتجر. تحقق من دور المدير وسياسات التخزين.',
    ProductImagesRepository.categoryIconsFolder =>
      'ليس للحساب صلاحية رفع أيقونات التصنيف. تحقق من دور الموظف وسياسات التخزين.',
    _ =>
      'ليس للحساب صلاحية رفع صور المنتجات. تحقق من دور الموظف وسياسات التخزين.',
  };
  final detail = _uploadErrorDetail(error);
  final status = _uploadStatusCode(error);
  final combined = '${error.runtimeType} $detail'.toLowerCase();

  if (status == 401) {
    return const ProductImageUploadException(
      code: 'UPLOAD_UNAUTHORIZED',
      message:
          'انتهت الجلسة أو غير صالحة. سجّل الدخول من جديد ثم أعد رفع الصورة.',
    );
  }
  if (status == 403 ||
      combined.contains('row-level security') ||
      combined.contains('unauthorized') ||
      combined.contains('not allowed')) {
    return ProductImageUploadException(
      code: 'UPLOAD_FORBIDDEN',
      message: forbiddenMessage,
    );
  }
  if (status == 404 || combined.contains('bucket not found')) {
    return const ProductImageUploadException(
      code: 'BUCKET_MISSING',
      message:
          'مجلد التخزين product-images غير موجود. طبّق ترحيلات التخزين ثم أعد المحاولة.',
    );
  }
  if (status == 409 ||
      combined.contains('duplicate') ||
      combined.contains('already exists')) {
    return const ProductImageUploadException(
      code: 'UPLOAD_CONFLICT',
      message: 'يوجد ملف بنفس الاسم في التخزين. حاول رفع الصورة من جديد.',
    );
  }
  if (status == 413 ||
      combined.contains('maximum allowed size') ||
      combined.contains('payload too large') ||
      combined.contains('exceeded the maximum')) {
    return const ProductImageUploadException(
      code: 'FILE_TOO_LARGE',
      message: 'حجم الصورة أكبر من 5 ميغابايت المسموح بها في التخزين.',
    );
  }
  if (status == 415 ||
      combined.contains('mime') ||
      combined.contains('content type') ||
      combined.contains('invalid file')) {
    return ProductImageUploadException(
      code: 'UNSUPPORTED_IMAGE',
      message: _withDetail(
        'نوع الصورة غير مسموح في التخزين. استخدم JPEG أو PNG أو WebP.',
        detail,
      ),
    );
  }
  if (status == 400) {
    return ProductImageUploadException(
      code: 'UPLOAD_REJECTED',
      message: _withDetail(
        'رفض التخزين ملف الصورة. تحقق من النوع والحجم والمسار.',
        detail,
      ),
    );
  }
  if (_isRevokedBlobFailure(combined)) {
    return const ProductImageUploadException(
      code: 'UPLOAD_BROWSER_FILE',
      message:
          'تعذر قراءة ملف الصورة في المتصفح. اختر الصورة مرة أخرى ثم أعد الرفع.',
    );
  }
  if (_isNetworkUploadFailure(combined)) {
    return ProductImageUploadException(
      code: 'UPLOAD_NETWORK',
      message: _withDetail(
        'تعذر الاتصال بخادم التخزين. تحقق من الشبكة أو إعدادات CORS للنطاق.',
        detail,
      ),
    );
  }
  if (combined.contains('permission denied') &&
      combined.contains('current_role')) {
    return const ProductImageUploadException(
      code: 'UPLOAD_FORBIDDEN',
      message:
          'سياسة التخزين لا تستطيع قراءة صلاحية الحساب. طبّق ترحيل صلاحيات current_role ثم أعد المحاولة.',
    );
  }
  return ProductImageUploadException(
    code: 'UPLOAD_FAILED',
    message: _withDetail(
      status == null
          ? 'تعذر رفع الصورة إلى التخزين.'
          : 'تعذر رفع الصورة إلى التخزين (رمز $status).',
      detail,
    ),
  );
}

int? _uploadStatusCode(Object error) {
  if (error is StorageException) {
    return int.tryParse(error.statusCode ?? '');
  }
  final match = RegExp(r'status(?:Code)?:\s*(\d{3})', caseSensitive: false)
      .firstMatch(error.toString());
  return match == null ? null : int.tryParse(match.group(1)!);
}

String _uploadErrorDetail(Object error) {
  if (error is StorageException) {
    final parts = [
      if ((error.error ?? '').trim().isNotEmpty) error.error!.trim(),
      if (error.message.trim().isNotEmpty) error.message.trim(),
    ];
    return parts.join(' — ');
  }
  return error.toString().trim();
}

bool _isRevokedBlobFailure(String combined) {
  return combined.contains('could not load blob') ||
      combined.contains('has it been revoked') ||
      combined.contains('cannot read bytes from blob');
}

bool _isNetworkUploadFailure(String combined) {
  return combined.contains('clientexception') ||
      combined.contains('socketexception') ||
      combined.contains('failed host lookup') ||
      combined.contains('failed to fetch') ||
      combined.contains('xmlhttprequest') ||
      combined.contains('cors') ||
      combined.contains('timed out') ||
      combined.contains('timeout') ||
      combined.contains('network is unreachable');
}

String _withDetail(String arabic, String detail) {
  final cleaned = detail
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'bearer\s+[a-z0-9._\-]+', caseSensitive: false), '')
      .trim();
  if (cleaned.isEmpty || _isTechnicalClientDump(cleaned)) return arabic;
  final clipped =
      cleaned.length > 160 ? '${cleaned.substring(0, 157)}...' : cleaned;
  return '$arabic\n$clipped';
}

bool _isTechnicalClientDump(String detail) {
  final lower = detail.toLowerCase();
  return lower.contains('exception:') ||
      lower.contains('could not load blob') ||
      lower.contains('has it been revoked') ||
      lower.startsWith('instance of');
}

class FileSelectorProductImagePicker implements ProductImagePicker {
  const FileSelectorProductImagePicker();

  @override
  Future<PickedProductImage?> pick() async {
    try {
      final picked = await pickBrowserProductImage(
        maxBytes: ProductImagesRepository.maxBytes,
      );
      if (picked == null) return null;
      return PickedProductImage(
        fileName: picked.fileName,
        bytes: picked.bytes,
      );
    } on BrowserPickedImageException catch (error) {
      throw ProductImageUploadException(
        code: error.code,
        message: error.message,
      );
    }
  }
}

class SupabaseProductImageStorageGateway implements ProductImageStorageGateway {
  SupabaseProductImageStorageGateway(this.client);

  final SupabaseClient client;

  @override
  String? get currentUserId => client.auth.currentUser?.id;

  @override
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
    ProductImageUploadProgress? onProgress,
  }) async {
    // storage_client 2.5 has no byte-level upload progress callback.
    onProgress?.call(null);
    await client.storage.from(ProductImagesRepository.bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '31536000',
            contentType: contentType,
            upsert: false,
          ),
        );
    onProgress?.call(1);
  }

  @override
  String publicUrl(String path) => client.storage
      .from(ProductImagesRepository.bucketName)
      .getPublicUrl(path);

  @override
  Future<void> remove(String path) async {
    await client.storage
        .from(ProductImagesRepository.bucketName)
        .remove([path]);
  }
}

class _ValidatedImageType {
  const _ValidatedImageType(this.extension, this.contentType);

  final String extension;
  final String contentType;
}
