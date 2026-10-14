import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/shop_branding_cache.dart';

class ShopBrandLogo extends StatelessWidget {
  const ShopBrandLogo({
    this.logoUrl,
    this.logoBytes,
    this.size = 40,
    this.backgroundColor,
    this.fallbackIconColor = Colors.white,
    this.semanticLabel = 'شعار المتجر',
    super.key,
  });

  final String? logoUrl;
  final Uint8List? logoBytes;
  final double size;
  final Color? backgroundColor;
  final Color fallbackIconColor;
  final String semanticLabel;

  /// Soft rounded-rect for uploaded logos (not a circle). Scales with [size]
  /// and stays in the 8–12dp band used across the app.
  static double cornerRadiusFor(double size) =>
      (size * 0.22).clamp(8.0, 12.0);

  String? get _resolvedLogoUrl =>
      logoUrl ?? ShopBrandingCache.current.logoUrl;

  bool get _hasCustomLogo {
    final url = _resolvedLogoUrl?.trim() ?? '';
    final bytes = logoBytes;
    return (bytes != null && bytes.isNotEmpty) || url.isNotEmpty;
  }

  Widget _fallbackMark() {
    return Icon(
      Icons.pets,
      color: fallbackIconColor,
      size: size * 0.56,
    );
  }

  Widget _fallbackBadge({required Color background}) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background,
        ),
        child: Center(child: _fallbackMark()),
      ),
    );
  }

  Widget _customLogoImage({required Color background}) {
    final url = _resolvedLogoUrl?.trim() ?? '';
    final bytes = logoBytes;
    final fallback = _fallbackBadge(background: background);

    final Widget image;
    if (bytes != null && bytes.isNotEmpty) {
      image = Image.memory(
        bytes,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } else {
      image = Image.network(
        url,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        // Canvas paint keeps width/height; HTML <img> can collapse to the
        // file's intrinsic size (a 16px scribble inside a grey chip).
        webHtmlElementStrategy: WebHtmlElementStrategy.never,
        loadingBuilder: (context, child, loadingProgress) =>
            loadingProgress == null ? child : fallback,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadiusFor(size)),
        clipBehavior: Clip.antiAlias,
        child: image,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = backgroundColor ?? Theme.of(context).colorScheme.primary;
    final child = _hasCustomLogo
        ? _customLogoImage(background: background)
        : _fallbackBadge(background: background);

    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(child: child),
    );
  }
}
