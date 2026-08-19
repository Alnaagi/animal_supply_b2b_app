import 'package:animal_supply_b2b/src/core/support/customer_last_active_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 18, 14, 30);

  test('never-signed-in customers get a clear Arabic fallback', () {
    expect(
        formatCustomerLastActiveAr(null, now: now), customerLastActiveNeverAr);
  });

  test('relative minutes and hours use Libyan-friendly Arabic', () {
    expect(
      formatCustomerLastActiveAr(
        now.subtract(const Duration(seconds: 20)),
        now: now,
      ),
      'آخر نشاط: الآن',
    );
    expect(
      formatCustomerLastActiveAr(
        now.subtract(const Duration(minutes: 1)),
        now: now,
      ),
      'آخر نشاط: منذ دقيقة',
    );
    expect(
      formatCustomerLastActiveAr(
        now.subtract(const Duration(minutes: 2)),
        now: now,
      ),
      'آخر نشاط: منذ دقيقتين',
    );
    expect(
      formatCustomerLastActiveAr(
        now.subtract(const Duration(minutes: 5)),
        now: now,
      ),
      'آخر نشاط: منذ 5 دقائق',
    );
    expect(
      formatCustomerLastActiveAr(
        now.subtract(const Duration(hours: 1, minutes: 10)),
        now: now,
      ),
      'آخر نشاط: منذ ساعة • 1:20 مساءً',
    );
    expect(
      formatCustomerLastActiveAr(
        now.subtract(const Duration(hours: 2)),
        now: now,
      ),
      'آخر نشاط: منذ ساعتين • 12:30 مساءً',
    );
    expect(
      formatCustomerLastActiveAr(
        now.subtract(const Duration(hours: 3)),
        now: now,
      ),
      'آخر نشاط: منذ 3 ساعات • 11:30 صباحاً',
    );
  });

  test('today, yesterday, and older days keep an optional 12-hour Arabic clock',
      () {
    expect(
      formatCustomerLastActiveAr(DateTime(2026, 8, 18, 9, 5), now: now),
      'آخر نشاط: منذ 5 ساعات • 9:05 صباحاً',
    );
    expect(
      formatCustomerLastActiveAr(DateTime(2026, 8, 17, 21, 15), now: now),
      'آخر نشاط: أمس • 9:15 مساءً',
    );
    expect(
      formatCustomerLastActiveAr(DateTime(2026, 8, 16, 8, 0), now: now),
      'آخر نشاط: منذ يومين • 8:00 صباحاً',
    );
    expect(
      formatCustomerLastActiveAr(DateTime(2026, 8, 10, 18, 40), now: now),
      'آخر نشاط: 10 أغسطس 2026 • 6:40 مساءً',
    );
  });

  test('clock uses 12-hour Arabic صباحاً / مساءً instead of 24-hour', () {
    expect(
      formatCustomerLastActiveAr(DateTime(2026, 8, 17, 14, 52), now: now),
      'آخر نشاط: أمس • 2:52 مساءً',
    );
    expect(
      formatCustomerLastActiveAr(DateTime(2026, 8, 17, 0, 30), now: now),
      'آخر نشاط: أمس • 12:30 صباحاً',
    );
    expect(
      formatCustomerLastActiveAr(DateTime(2026, 8, 17, 12, 0), now: now),
      'آخر نشاط: أمس • 12:00 مساءً',
    );
    expect(
      formatCustomerLastActiveAr(DateTime(2026, 8, 17, 11, 59), now: now),
      'آخر نشاط: أمس • 11:59 صباحاً',
    );

    final yesterdayAfternoon = formatCustomerLastActiveAr(
      DateTime(2026, 8, 17, 14, 52),
      now: now,
    );
    expect(yesterdayAfternoon, isNot(contains('14:52')));
    expect(yesterdayAfternoon, contains('مساءً'));
    expect(yesterdayAfternoon, contains('أمس'));
  });
}
