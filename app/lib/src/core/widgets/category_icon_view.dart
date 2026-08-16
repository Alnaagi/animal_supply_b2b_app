import 'package:flutter/material.dart';

import '../../data/models/category_icon.dart';
import '../../data/models/product_category.dart';
import '../theme/app_theme.dart';

class CategoryIconView extends StatelessWidget {
  const CategoryIconView({
    super.key,
    this.iconKey,
    this.iconUrl,
    this.name = '',
    this.size = 24,
    this.color = AppTheme.green,
  });

  factory CategoryIconView.fromCategory(
    ProductCategory category, {
    Key? key,
    double size = 24,
    Color color = AppTheme.green,
  }) {
    return CategoryIconView(
      key: key,
      iconKey: category.iconKey,
      iconUrl: category.iconUrl,
      name: category.name,
      size: size,
      color: color,
    );
  }

  final String? iconKey;
  final String? iconUrl;
  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final url = iconUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _glyph(),
        ),
      );
    }
    return _glyph();
  }

  Widget _glyph() {
    return Icon(
      CategoryIconCatalog.iconData(iconKey: iconKey, fallbackName: name),
      size: size,
      color: color,
    );
  }
}
