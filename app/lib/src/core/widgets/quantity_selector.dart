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
    final canDecrease = quantity > min;
    final canIncrease = max == null || quantity < max!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            tooltip: 'تقليل الكمية',
            icon: Icons.remove,
            enabled: canDecrease,
            onPressed: () => onChanged(quantity - 1),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            alignment: Alignment.center,
            child: Semantics(
              label: 'الكمية الحالية: $quantity',
              child: ExcludeSemantics(
                child: Text(
                  '$quantity',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppTheme.darkGreen,
                  ),
                ),
              ),
            ),
          ),
          _StepperButton(
            tooltip: 'زيادة الكمية',
            icon: Icons.add,
            enabled: canIncrease,
            onPressed: () => onChanged(quantity + 1),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      iconSize: 20,
      icon: Icon(
        icon,
        color: enabled ? AppTheme.green : Colors.grey.shade400,
      ),
    );
  }
}
