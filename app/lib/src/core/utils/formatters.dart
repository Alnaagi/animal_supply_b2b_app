import 'package:intl/intl.dart';

final _lyd =
    NumberFormat.currency(locale: 'ar_LY', symbol: 'د.ل', decimalDigits: 2);

/// Western digits for print/PDF. In-app Arabic copy still uses [lyd].
final _lydWestern = NumberFormat.currency(
  locale: 'en_US',
  symbol: 'د.ل',
  decimalDigits: 2,
);

String lyd(num value) => _lyd.format(value);

String lydWestern(num value) => _lydWestern.format(value);

const _easternDigits = '٠١٢٣٤٥٦٧٨٩';
const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';
const _westernDigits = '0123456789';

/// Keeps Arabic text but forces ASCII 0-9 (and Western separators) for PDFs.
String westernDigits(String value) {
  final buffer = StringBuffer();
  for (final character in value.split('')) {
    final easternIndex = _easternDigits.indexOf(character);
    if (easternIndex >= 0) {
      buffer.write(_westernDigits[easternIndex]);
      continue;
    }
    final persianIndex = _persianDigits.indexOf(character);
    if (persianIndex >= 0) {
      buffer.write(_westernDigits[persianIndex]);
      continue;
    }
    if (character == '٫') {
      buffer.write('.');
      continue;
    }
    if (character == '٬') {
      buffer.write(',');
      continue;
    }
    buffer.write(character);
  }
  return buffer.toString();
}
