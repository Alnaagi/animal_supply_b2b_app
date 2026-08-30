import 'package:flutter/material.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final canDecrease = quantity > min;
    final canIncrease = max == null || quantity < max!;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline),
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
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      iconSize: 20,
      icon: Icon(
        icon,
        color:
            enabled ? scheme.primary : scheme.onSurface.withValues(alpha: .38),
      ),
    );
  }
}
