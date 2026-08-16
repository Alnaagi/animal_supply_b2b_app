import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ShopBrandLogo extends StatelessWidget {
  const ShopBrandLogo({
    this.logoUrl,
    this.logoBytes,
    this.size = 40,
    this.backgroundColor = AppTheme.green,
    this.fallbackIconColor = Colors.white,
    this.semanticLabel = 'شعار المتجر',
    super.key,
  });

  final String? logoUrl;
  final Uint8List? logoBytes;
  final double size;
  final Color backgroundColor;
  final Color fallbackIconColor;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim() ?? '';
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
      ),
      child: Icon(
        Icons.pets,
        color: fallbackIconColor,
        size: size * 0.56,
      ),
    );
    final bytes = logoBytes;
    final Widget image;
    if (bytes != null && bytes.isNotEmpty) {
      image = ClipOval(
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      );
    } else if (url.isEmpty) {
      image = fallback;
    } else {
      image = ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          loadingBuilder: (context, child, loadingProgress) =>
              loadingProgress == null ? child : fallback,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      );
    }
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(child: image),
    );
  }
}
