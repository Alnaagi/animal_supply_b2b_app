import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

abstract interface class ProductImageStorageGateway {
  String? get currentUserId;

  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
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
  static const maxBytes = 5 * 1024 * 1024;

  final ProductImagePicker _picker;
  final ProductImageStorageGateway? _storage;
  final String Function() _randomId;

  bool get canUpload =>
      _storage != null && (_storage.currentUserId?.trim().isNotEmpty ?? false);

  Future<ProductImageUploadResult?> pickAndUpload({
    String folder = productsFolder,
  }) =>
      _pickAndUpload(folder: folder);

  Future<ProductImageUploadResult?> pickAndUploadBanner() =>
      _pickAndUpload(folder: bannersFolder);

  Future<ProductImageUploadResult?> _pickAndUpload({
    required String folder,
  }) async {
    final storage = _storage;
    final ownerId = storage?.currentUserId?.trim();
    if (storage == null || ownerId == null || ownerId.isEmpty) {
      throw const ProductImageUploadException(
        code: 'BACKEND_REQUIRED',
        message:
            'رفع الصور يحتاج ربط Supabase الإنتاجي وتسجيل دخول إداري. استخدم رابط HTTPS يدوياً حالياً.',
      );
    }
    if (folder != productsFolder && folder != bannersFolder) {
      throw const ProductImageUploadException(
        code: 'INVALID_FOLDER',
        message: 'مسار رفع الصورة غير مدعوم.',
      );
    }

    final picked = await _picker.pick();
    if (picked == null) return null;
    final type = _validatedType(picked.fileName, picked.bytes);
    final randomId = _randomId().replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');
    if (randomId.isEmpty) {
      throw const ProductImageUploadException(
        code: 'INVALID_RANDOM_PATH',
        message: 'تعذر إنشاء مسار آمن للصورة. حاول من جديد.',
      );
    }
    final path = '$folder/$ownerId/$randomId.${type.extension}';
    final forbiddenMessage = folder == bannersFolder
        ? 'ليس للحساب صلاحية رفع صور البانرات. تحقق من دور الموظف وسياسات التخزين.'
        : 'ليس للحساب صلاحية رفع صور المنتجات. تحقق من دور الموظف وسياسات التخزين.';

    try {
      await storage.upload(
        path: path,
        bytes: picked.bytes,
        contentType: type.contentType,
      );
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
    } on StorageException catch (error) {
      final forbidden = error.statusCode == '401' || error.statusCode == '403';
      throw ProductImageUploadException(
        code: forbidden ? 'UPLOAD_FORBIDDEN' : 'UPLOAD_FAILED',
        message: forbidden
            ? forbiddenMessage
            : 'تعذر رفع الصورة إلى التخزين. تحقق من الاتصال ثم حاول من جديد.',
      );
    } catch (_) {
      throw const ProductImageUploadException(
        code: 'UPLOAD_FAILED',
        message:
            'تعذر رفع الصورة إلى التخزين. تحقق من الاتصال ثم حاول من جديد.',
      );
    }
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

class FileSelectorProductImagePicker implements ProductImagePicker {
  const FileSelectorProductImagePicker();

  @override
  Future<PickedProductImage?> pick() async {
    const types = XTypeGroup(
      label: 'صور المنتجات',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
      uniformTypeIdentifiers: [
        'public.jpeg',
        'public.png',
        'org.webmproject.webp',
      ],
    );
    final file = await openFile(
      acceptedTypeGroups: const [types],
      confirmButtonText: 'اختيار الصورة',
    );
    if (file == null) return null;
    final length = await file.length();
    if (length > ProductImagesRepository.maxBytes) {
      throw const ProductImageUploadException(
        code: 'FILE_TOO_LARGE',
        message: 'حجم الصورة أكبر من 5 MiB.',
      );
    }
    return PickedProductImage(
      fileName: file.name,
      bytes: await file.readAsBytes(),
    );
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
  }) async {
    await client.storage.from(ProductImagesRepository.bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '31536000',
            contentType: contentType,
            upsert: false,
          ),
        );
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
