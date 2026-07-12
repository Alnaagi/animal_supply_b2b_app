import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/local_cache.dart';
import '../models/product.dart';
import '../remote/supabase_clients.dart';
import 'demo_data.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(cache: ref.watch(localCacheProvider)),
);

class CatalogRepository {
  CatalogRepository({LocalCache? cache}) : _cache = cache;

  final LocalCache? _cache;
  final List<Product> _demoProducts = [...demoProducts];

  Future<List<Product>> products({String query = '', String? category}) async {
    final client = supabaseClient;
    if (client != null) {
      try {
        final rows = await client
            .from('products')
            .select('*, categories(name)')
            .order('created_at', ascending: false);
        final products =
            rows.map<Product>((row) => Product.fromSupabase(row)).toList();
        await _cache?.saveProducts(products);
        return _filterProducts(products, query: query, category: category);
      } catch (_) {
        final cached = await _cache?.cachedProducts() ?? const <Product>[];
        if (cached.isNotEmpty) {
          return _filterProducts(cached, query: query, category: category);
        }
        rethrow;
      }
    }
    final demo = _demoProducts.where((p) => p.active).toList();
    await _cache?.saveProducts(demo);
    return _filterProducts(demo, query: query, category: category);
  }

  Future<List<String>> categories() async {
    final client = supabaseClient;
    if (client != null) {
      try {
        final rows = await client
            .from('categories')
            .select('name')
            .eq('active', true)
            .order('name');
        return [for (final row in rows) row['name'].toString()];
      } catch (_) {
        final cached = await _cache?.cachedProducts() ?? const <Product>[];
        if (cached.isNotEmpty) {
          return cached.map((p) => p.category).toSet().toList();
        }
        rethrow;
      }
    }
    return _demoProducts.map((p) => p.category).toSet().toList();
  }

  Future<Product?> productById(String id) async {
    final client = supabaseClient;
    if (client != null) {
      try {
        final row = await client
            .from('products')
            .select('*, categories(name)')
            .eq('id', id)
            .maybeSingle();
        return row == null ? null : Product.fromSupabase(row);
      } catch (_) {
        final cached = await _cache?.cachedProducts() ?? const <Product>[];
        for (final product in cached) {
          if (product.id == id) return product;
        }
        rethrow;
      }
    }
    for (final product in _demoProducts) {
      if (product.id == id) return product;
    }
    return null;
  }

  Future<Product> saveProduct(Product product) async {
    final client = supabaseClient;
    if (client != null) {
      final categoryId = await _categoryIdFor(product.category);
      final map = product.toSupabaseMap(categoryUuid: categoryId);
      final saved =
          product.id.startsWith('demo-') || product.id.startsWith('local-')
              ? await client
                  .from('products')
                  .insert(map)
                  .select('*, categories(name)')
                  .single()
              : await client
                  .from('products')
                  .update(map)
                  .eq('id', product.id)
                  .select('*, categories(name)')
                  .single();
      return Product.fromSupabase(saved);
    }
    final index = _demoProducts.indexWhere((item) => item.id == product.id);
    if (index == -1) {
      _demoProducts.insert(0, product);
    } else {
      _demoProducts[index] = product;
    }
    await _cache?.saveProducts(_demoProducts.where((p) => p.active).toList());
    return product;
  }

  Future<void> archiveProduct(String id) async {
    final client = supabaseClient;
    if (client != null) {
      await client.from('products').update({
        'active': false,
        'archived_at': DateTime.now().toIso8601String()
      }).eq('id', id);
      return;
    }
    final index = _demoProducts.indexWhere((product) => product.id == id);
    if (index != -1) {
      _demoProducts[index] = _demoProducts[index].copyWith(isActive: false);
    }
    await _cache?.saveProducts(_demoProducts.where((p) => p.active).toList());
  }

  List<Product> _filterProducts(
    List<Product> products, {
    required String query,
    String? category,
  }) {
    final q = query.trim().toLowerCase();
    return products.where((p) {
      return (category == null || p.category == category) &&
          (q.isEmpty ||
              p.name.contains(q) ||
              p.category.contains(q) ||
              (p.nameEn?.toLowerCase().contains(q) ?? false) ||
              p.sku.toLowerCase().contains(q) ||
              p.brand.toLowerCase().contains(q) ||
              p.tags.any((tag) => tag.toLowerCase().contains(q)));
    }).toList();
  }

  Future<String?> _categoryIdFor(String categoryName) async {
    final client = supabaseClient;
    if (client == null) return null;
    final existing = await client
        .from('categories')
        .select('id')
        .eq('name', categoryName)
        .maybeSingle();
    if (existing != null) return existing['id'].toString();
    final inserted = await client
        .from('categories')
        .insert({'name': categoryName})
        .select('id')
        .single();
    return inserted['id'].toString();
  }
}
