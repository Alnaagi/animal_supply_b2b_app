import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../admin_dashboard/admin_shell.dart';

class AdminProductsScreen extends ConsumerStatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  ConsumerState<AdminProductsScreen> createState() =>
      _AdminProductsScreenState();
}

class _AdminProductsScreenState extends ConsumerState<AdminProductsScreen> {
  final search = TextEditingController();
  String? category;
  int refreshKey = 0;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'إدارة المنتجات',
      actions: [
        IconButton(
            onPressed: () => _showProductForm(),
            icon: const Icon(Icons.add_box),
            tooltip: 'منتج جديد')
      ],
      child: FutureBuilder<List<Product>>(
        key: ValueKey(refreshKey),
        future: ref
            .read(catalogRepositoryProvider)
            .products(query: search.text, category: category),
        builder: (context, snapshot) {
          final products = snapshot.data ?? const <Product>[];
          final categories = products.map((p) => p.category).toSet().toList();
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 360,
                      child: TextField(
                        controller: search,
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'بحث بالاسم أو SKU أو العلامة'),
                        onSubmitted: (_) => setState(() => refreshKey++),
                      ),
                    ),
                    ChoiceChip(
                        label: const Text('الكل'),
                        selected: category == null,
                        onSelected: (_) => setState(() => category = null)),
                    for (final c in categories.take(8))
                      ChoiceChip(
                          label: Text(c),
                          selected: category == c,
                          onSelected: (_) => setState(() => category = c)),
                    FilledButton.icon(
                        onPressed: () => _showProductForm(),
                        icon: const Icon(Icons.add),
                        label: const Text('منتج جديد')),
                  ]),
              const SizedBox(height: 14),
              if (products.isEmpty)
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.inventory_2_outlined),
                        title: Text('لا توجد منتجات بهذا البحث')))
              else
                for (final product in products)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                          backgroundColor: product.lowStock
                              ? AppTheme.orange
                              : AppTheme.green,
                          child: const Icon(Icons.inventory_2,
                              color: Colors.white)),
                      title: Text(product.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${product.sku} • ${product.category} • ${product.brand}\nمخزون ${product.stockQuantity} • أقل طلب ${product.minOrderQty} • ${product.active ? 'نشط' : 'مؤرشف'}'),
                      isThreeLine: true,
                      trailing: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(lyd(product.price),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  _showProductForm(product);
                                } else if (value == 'archive') {
                                  await ref
                                      .read(catalogRepositoryProvider)
                                      .archiveProduct(product.id);
                                  setState(() => refreshKey++);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                    value: 'edit', child: Text('تعديل')),
                                PopupMenuItem(
                                    value: 'archive', child: Text('أرشفة')),
                              ],
                            ),
                          ]),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showProductForm([Product? product]) async {
    final editing = product != null;
    final name = TextEditingController(text: product?.nameAr ?? '');
    final nameEn = TextEditingController(text: product?.nameEn ?? '');
    final sku = TextEditingController(text: product?.sku ?? '');
    final category = TextEditingController(text: product?.category ?? 'قطط');
    final animalType = TextEditingController(text: product?.animalType ?? '');
    final brand = TextEditingController(text: product?.brand ?? '');
    final unitSize = TextEditingController(text: product?.unitSize ?? '');
    final packageSize = TextEditingController(text: product?.packageSize ?? '');
    final price = TextEditingController(
        text: product?.basePrice.toStringAsFixed(2) ?? '');
    final oldPrice = TextEditingController(
        text: product?.oldPrice?.toStringAsFixed(2) ?? '');
    final discount =
        TextEditingController(text: product?.discountPercent?.toString() ?? '');
    final stock =
        TextEditingController(text: product?.stockQuantity.toString() ?? '0');
    final moq =
        TextEditingController(text: product?.minOrderQty.toString() ?? '1');
    final image = TextEditingController(text: product?.imageUrl ?? '');
    final description =
        TextEditingController(text: product?.descriptionAr ?? '');
    var active = product?.isActive ?? true;
    var featured = product?.isFeatured ?? false;
    var topSelling = product?.isTopSelling ?? false;

    final saved = await showDialog<Product>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(editing ? 'تعديل منتج' : 'منتج جديد'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(children: [
                TextField(
                    controller: name,
                    decoration:
                        const InputDecoration(labelText: 'الاسم العربي')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: sku,
                          decoration: const InputDecoration(labelText: 'SKU'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: brand,
                          decoration: const InputDecoration(
                              labelText: 'العلامة التجارية'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: category,
                          decoration:
                              const InputDecoration(labelText: 'التصنيف'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: animalType,
                          decoration:
                              const InputDecoration(labelText: 'نوع الحيوان'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: unitSize,
                          decoration:
                              const InputDecoration(labelText: 'حجم الوحدة'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: packageSize,
                          decoration:
                              const InputDecoration(labelText: 'حجم العبوة'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: price,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'السعر الأساسي LYD'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: stock,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'المخزون'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: moq,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'أقل طلب'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: oldPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'سعر قديم اختياري'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: discount,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'نسبة الخصم'))),
                ]),
                const SizedBox(height: 10),
                TextField(
                    controller: image,
                    decoration:
                        const InputDecoration(labelText: 'رابط صورة المنتج')),
                const SizedBox(height: 10),
                TextField(
                    controller: nameEn,
                    decoration: const InputDecoration(
                        labelText: 'الاسم الإنجليزي اختياري')),
                const SizedBox(height: 10),
                TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'الوصف')),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  FilterChip(
                      label: const Text('نشط'),
                      selected: active,
                      onSelected: (v) => setDialogState(() => active = v)),
                  FilterChip(
                      label: const Text('مميز'),
                      selected: featured,
                      onSelected: (v) => setDialogState(() => featured = v)),
                  FilterChip(
                      label: const Text('الأكثر طلباً'),
                      selected: topSelling,
                      onSelected: (v) => setDialogState(() => topSelling = v)),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final parsedPrice = double.tryParse(price.text) ?? -1;
                final parsedStock = int.tryParse(stock.text) ?? -1;
                final parsedMoq = int.tryParse(moq.text) ?? 0;
                if (name.text.trim().isEmpty ||
                    sku.text.trim().isEmpty ||
                    parsedPrice < 0 ||
                    parsedStock < 0 ||
                    parsedMoq < 1) {
                  return;
                }
                Navigator.pop(
                  context,
                  Product(
                    id: product?.id ?? 'local-${const Uuid().v4()}',
                    nameAr: name.text.trim(),
                    nameEn:
                        nameEn.text.trim().isEmpty ? null : nameEn.text.trim(),
                    sku: sku.text.trim(),
                    category: category.text.trim(),
                    animalType: animalType.text.trim(),
                    brand: brand.text.trim(),
                    unitSize: unitSize.text.trim(),
                    packageSize: packageSize.text.trim().isEmpty
                        ? null
                        : packageSize.text.trim(),
                    basePrice: parsedPrice,
                    oldPrice: double.tryParse(oldPrice.text),
                    discountPercent: int.tryParse(discount.text),
                    stockQuantity: parsedStock,
                    minOrderQty: parsedMoq,
                    descriptionAr: description.text.trim(),
                    imageUrl:
                        image.text.trim().isEmpty ? null : image.text.trim(),
                    isActive: active,
                    isFeatured: featured,
                    isTopSelling: topSelling,
                    tags: [
                      category.text.trim(),
                      brand.text.trim(),
                      animalType.text.trim()
                    ].where((tag) => tag.isNotEmpty).toList(),
                  ),
                );
              },
              child: const Text('حفظ المنتج'),
            ),
          ],
        ),
      ),
    );

    for (final controller in [
      name,
      nameEn,
      sku,
      category,
      animalType,
      brand,
      unitSize,
      packageSize,
      price,
      oldPrice,
      discount,
      stock,
      moq,
      image,
      description
    ]) {
      controller.dispose();
    }
    if (saved == null) return;
    await ref.read(catalogRepositoryProvider).saveProduct(saved);
    setState(() => refreshKey++);
  }
}
