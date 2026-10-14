import 'package:flutter/material.dart';

import '../utils/formatters.dart';

class PriceText extends StatelessWidget {
  const PriceText({required this.price, this.oldPrice, super.key});
  final num price;
  final num? oldPrice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(lyd(price),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800, color: scheme.onSurface)),
        if (oldPrice != null)
          Text(
            lyd(oldPrice!),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                decoration: TextDecoration.lineThrough, color: Colors.grey),
          ),
      ],
    );
  }
}
