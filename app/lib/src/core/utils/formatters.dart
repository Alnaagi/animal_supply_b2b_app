import 'package:intl/intl.dart';

final _lyd =
    NumberFormat.currency(locale: 'ar_LY', symbol: 'د.ل', decimalDigits: 2);

String lyd(num value) => _lyd.format(value);
