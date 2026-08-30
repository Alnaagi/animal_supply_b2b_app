import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/updates/update_link.dart';
import '../../core/widgets/category_icon_view.dart';
import '../../data/models/category_icon.dart';
import '../../data/models/product_category.dart';
import '../../data/repositories/product_images_repository.dart';

class CategoryEditorResult {
  const CategoryEditorResult({
    required this.name,
    this.iconKey,
    this.iconUrl,
  });

  final String name;
  final String? iconKey;
  final String? iconUrl;
}

Future<CategoryEditorResult?> showCategoryEditorDialog({
  required BuildContext context,
  ProductCategory? existing,
}) {
  return showDialog<CategoryEditorResult>(
    context: context,
    builder: (context) => CategoryEditorDialog(existing: existing),
  );
}

class CategoryEditorDialog extends ConsumerStatefulWidget {
  const CategoryEditorDialog({super.key, this.existing});

  final ProductCategory? existing;

  @override
  ConsumerState<CategoryEditorDialog> createState() =>
      _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends ConsumerState<CategoryEditorDialog> {
  final _nameController = TextEditingController();
  final _httpsController = TextEditingController();
  final _iconFieldKey = GlobalKey();
  final _scrollController = ScrollController();

  String? _selectedKey;
  String? _uploadedUrl;
  Uint8List? _previewBytes;
  String? _nameError;
  String? _iconError;
  String? _uploadError;
  bool _uploading = false;
  double? _uploadProgress;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) return;
    _nameController.text = existing.name;
    final url = existing.iconUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      _uploadedUrl = url;
      _httpsController.text = url;
      return;
    }
    final key = existing.iconKey?.trim() ?? '';
    if (key.isNotEmpty) {
      _selectedKey = CategoryIconCatalog.isKnownKey(key)
          ? key
          : CategoryIconCatalog.defaultKey;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _httpsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  CategoryIconSelection get _selection {
    final url = (_uploadedUrl ?? _httpsController.text).trim();
    if (url.isNotEmpty) {
      return CategoryIconSelection(iconUrl: url);
    }
    final key = _selectedKey?.trim() ?? '';
    if (key.isNotEmpty) {
      return CategoryIconSelection(iconKey: key);
    }
    return const CategoryIconSelection();
  }

  void _revealIconField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _iconFieldKey.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.08,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _submit() {
    final name = _nameController.text.trim();
    var nameError = name.isEmpty ? 'أدخل اسم التصنيف.' : null;
    final selection = _selection;
    String? iconError;
    if (!selection.hasIcon) {
      iconError = 'اختر أيقونة جاهزة أو ارفع أيقونة للتصنيف.';
    } else if ((selection.iconUrl ?? '').isNotEmpty &&
        safeHttpsUpdateUri(selection.iconUrl!) == null) {
      iconError =
          'استخدم رابط https صالحاً ومن دون بيانات دخول، أو اختر أيقونة جاهزة.';
    }

    if (nameError != null || iconError != null) {
      setState(() {
        _nameError = nameError;
        _iconError = iconError;
      });
      if (iconError != null) _revealIconField();
      return;
    }

    Navigator.pop(
      context,
      CategoryEditorResult(
        name: name,
        iconKey: selection.iconKey,
        iconUrl: selection.iconUrl,
      ),
    );
  }

  Future<void> _uploadIcon() async {
    final images = ref.read(productImagesRepositoryProvider);
    setState(() {
      _uploadError = null;
      _iconError = null;
    });
    try {
      final picked = await images.pick();
      if (!mounted || picked == null) return;
      setState(() {
        _previewBytes = picked.bytes;
        _uploading = true;
        _uploadProgress = 0;
        _selectedKey = null;
      });
      if (!images.canUpload) {
        throw const ProductImageUploadException(
          code: 'BACKEND_REQUIRED',
          message:
              'رفع أيقونات التصنيف يحتاج ربط Supabase الإنتاجي وتسجيل دخول إداري. استخدم أيقونة جاهزة أو رابط HTTPS حالياً.',
        );
      }
      final result = await images.uploadPicked(
        picked,
        folder: ProductImagesRepository.categoryIconsFolder,
        onProgress: (fraction) {
          if (!mounted) return;
          setState(() => _uploadProgress = fraction);
        },
      );
      if (!mounted) return;
      setState(() {
        _uploadedUrl = result.publicUrl;
        _httpsController.text = result.publicUrl;
        _uploading = false;
        _uploadProgress = 1;
        _selectedKey = null;
        _iconError = null;
      });
    } on ProductImageUploadException catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadError = 'تعذر رفع أيقونة التصنيف. حاول مجدداً.';
      });
    }
  }

  void _selectPreset(String key) {
    setState(() {
      _selectedKey = key;
      _uploadedUrl = null;
      _previewBytes = null;
      _httpsController.clear();
      _iconError = null;
      _uploadError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final images = ref.watch(productImagesRepositoryProvider);
    final previewUrl = _uploadedUrl ?? _httpsController.text.trim();
    return AlertDialog(
      title: Text(_isEdit ? 'تعديل التصنيف' : 'إنشاء تصنيف جديد'),
      content: SizedBox(
        width: 480,
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('new-category-name-field'),
                  controller: _nameController,
                  autofocus: !_isEdit,
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_nameError == null) return;
                    setState(() => _nameError = null);
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.category_outlined),
                    labelText: 'اسم التصنيف',
                    helperText: 'سيظهر في اختيار التصنيف عند إضافة المنتجات.',
                    errorText: _nameError,
                  ),
                ),
                const SizedBox(height: 16),
                KeyedSubtree(
                  key: _iconFieldKey,
                  child: InputDecorator(
                    key: const ValueKey('category-icon-picker'),
                    decoration: InputDecoration(
                      labelText: 'أيقونة التصنيف',
                      helperText:
                          'يجب اختيار أيقونة جاهزة أو رفع صورة قبل الحفظ.',
                      errorText: _iconError,
                      border: const OutlineInputBorder(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: CircleAvatar(
                            radius: 28,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: .12),
                            child: _previewBytes != null
                                ? ClipOval(
                                    child: Image.memory(
                                      _previewBytes!,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : CategoryIconView(
                                    iconKey: _selectedKey,
                                    iconUrl: previewUrl,
                                    name: _nameController.text,
                                    size: 28,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final preset in CategoryIconCatalog.presets)
                              ChoiceChip(
                                key: ValueKey(
                                  'category-icon-preset-${preset.key}',
                                ),
                                avatar: Icon(preset.icon, size: 18),
                                label: Text(preset.labelAr),
                                selected: _selectedKey == preset.key &&
                                    (_uploadedUrl == null ||
                                        _uploadedUrl!.isEmpty),
                                onSelected: (_) => _selectPreset(preset.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const ValueKey('category-icon-upload-button'),
                          onPressed: _uploading ? null : _uploadIcon,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: Text(
                            _uploading ? 'جارٍ رفع الأيقونة...' : 'رفع أيقونة',
                          ),
                        ),
                        if (_uploading) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _uploadProgress,
                          ),
                        ],
                        if (!images.canUpload) ...[
                          const SizedBox(height: 8),
                          Text(
                            'وضع العرض أو عدم ربط الإنتاج: استخدم أيقونة جاهزة، أو أدخل رابط HTTPS. الرفع للتخزين يحتاج حساباً إنتاجياً.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[700]),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          key: const ValueKey('category-icon-https-field'),
                          controller: _httpsController,
                          enabled: !_uploading,
                          decoration: const InputDecoration(
                            labelText: 'أو رابط https للأيقونة',
                            hintText: 'https://',
                          ),
                          onChanged: (value) {
                            setState(() {
                              _uploadedUrl =
                                  value.trim().isEmpty ? null : value.trim();
                              if (value.trim().isNotEmpty) {
                                _selectedKey = null;
                              }
                              _iconError = null;
                            });
                          },
                        ),
                        if (_uploadError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _uploadError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          key: const ValueKey('save-category-button'),
          onPressed: _uploading ? null : _submit,
          icon: Icon(_isEdit ? Icons.save_outlined : Icons.add),
          label: Text(_isEdit ? 'حفظ التصنيف' : 'إنشاء التصنيف'),
        ),
      ],
    );
  }
}
