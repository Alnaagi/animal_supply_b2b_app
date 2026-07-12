import 'package:flutter/material.dart';

import '../constants/order_status.dart';
import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, this.color, super.key});
  final String label;
  final Color? color;

  factory StatusChip.order(OrderStatus status) {
    final c = switch (status) {
      OrderStatus.pending => AppTheme.orange,
      OrderStatus.confirmed => AppTheme.green,
      OrderStatus.preparing => Colors.blue,
      OrderStatus.ready => Colors.purple,
      OrderStatus.delivered => AppTheme.darkGreen,
      OrderStatus.cancelled => AppTheme.red,
    };
    return StatusChip(label: status.label, color: c);
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: c.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style:
              TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
