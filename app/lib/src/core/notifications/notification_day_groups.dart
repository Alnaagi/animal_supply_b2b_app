import '../../data/models/app_notification.dart';

class NotificationDayGroup {
  const NotificationDayGroup({
    required this.label,
    required this.items,
  });

  final String label;
  final List<AppNotification> items;
}

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

const _arabicWeekdays = <String>[
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

String arabicNotificationDayLabel(
  DateTime createdAt, {
  DateTime? now,
}) {
  final clock = (now ?? DateTime.now()).toLocal();
  final local = createdAt.toLocal();
  final today = DateTime(clock.year, clock.month, clock.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  return '${_arabicWeekdays[local.weekday - 1]} ${local.day} '
      '${_arabicMonths[local.month - 1]} ${local.year}';
}

List<NotificationDayGroup> groupNotificationsByDay(
  List<AppNotification> notifications, {
  DateTime? now,
}) {
  final groups = <NotificationDayGroup>[];
  for (final notification in notifications) {
    final label = arabicNotificationDayLabel(notification.createdAt, now: now);
    if (groups.isEmpty || groups.last.label != label) {
      groups.add(NotificationDayGroup(label: label, items: [notification]));
    } else {
      groups.last.items.add(notification);
    }
  }
  return groups;
}
