import 'package:animal_supply_b2b/src/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('westernDigits keeps Arabic words and forces Latin 0-9', () {
    expect(westernDigits('فاتورة ١٢٣٫٥٠'), 'فاتورة 123.50');
    expect(westernDigits('طلب ۴۲'), 'طلب 42');
    expect(lydWestern(60), contains('60.00'));
    expect(lydWestern(60), isNot(contains('٦')));
  });
}
