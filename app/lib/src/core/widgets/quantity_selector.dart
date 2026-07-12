import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class QuantitySelector extends StatelessWidget {
  const QuantitySelector(
      {required this.quantity,
      required this.min,
      required this.onChanged,
      this.max,
      super.key});
  final int quantity;
  final int min;
  final int? max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: AppTheme.softGray, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              onPressed: quantity <= min ? null : () => onChanged(quantity - 1),
              icon: const Icon(Icons.remove)),
          Text('$quantity',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
              onPressed: max != null && quantity >= max!
                  ? null
                  : () => onChanged(quantity + 1),
              icon: const Icon(Icons.add, color: AppTheme.orange)),
        ],
      ),
    );
  }
}
