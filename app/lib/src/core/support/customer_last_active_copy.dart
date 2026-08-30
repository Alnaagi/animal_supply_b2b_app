const customerLastActiveNeverAr = 'لم يسجّل دخولاً بعد';

const _arabicMonths = <String>[
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// Libyan-friendly relative last-active line for admin customer cards.
String formatCustomerLastActiveAr(
  DateTime? lastActiveAt, {
  DateTime? now,
}) {
  if (lastActiveAt == null) return customerLastActiveNeverAr;

  final clock = (now ?? DateTime.now()).toLocal();
  final local = lastActiveAt.toLocal();
  final elapsed = clock.difference(local);
  final time = _clock(local);

  if (elapsed.isNegative || elapsed.inSeconds < 45) {
    return 'آخر نشاط: الآن';
  }

  if (elapsed.inMinutes < 60) {
    return 'آخر نشاط: ${_minutesAgo(elapsed.inMinutes)}';
  }

  final today = DateTime(clock.year, clock.month, clock.day);
  final day = DateTime(local.year, local.month, local.day);
  final dayDiff = today.difference(day).inDays;

  if (dayDiff == 0) {
    return 'آخر نشاط: ${_hoursAgo(elapsed.inHours)} • $time';
  }
  if (dayDiff == 1) {
    return 'آخر نشاط: أمس • $time';
  }
  if (dayDiff == 2) {
    return 'آخر نشاط: منذ يومين • $time';
  }
  if (dayDiff < 7) {
    return 'آخر نشاط: منذ $dayDiff أيام • $time';
  }

  return 'آخر نشاط: ${local.day} ${_arabicMonths[local.month - 1]} '
      '${local.year} • $time';
}

String _clock(DateTime value) {
  final hour24 = value.hour;
  final period = hour24 < 12 ? 'صباحاً' : 'مساءً';
  var hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour12:$minute $period';
}

String _minutesAgo(int minutes) {
  if (minutes <= 1) return 'منذ دقيقة';
  if (minutes == 2) return 'منذ دقيقتين';
  if (minutes <= 10) return 'منذ $minutes دقائق';
  return 'منذ $minutes دقيقة';
}

String _hoursAgo(int hours) {
  if (hours <= 1) return 'منذ ساعة';
  if (hours == 2) return 'منذ ساعتين';
  if (hours <= 10) return 'منذ $hours ساعات';
  return 'منذ $hours ساعة';
}
