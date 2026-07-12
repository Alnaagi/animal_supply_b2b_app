enum OrderStatus {
  pending('pending', 'قيد المراجعة'),
  confirmed('confirmed', 'مؤكد'),
  preparing('preparing', 'قيد التجهيز'),
  ready('ready', 'جاهز'),
  delivered('delivered', 'تم التسليم'),
  cancelled('cancelled', 'ملغي');

  const OrderStatus(this.value, this.label);
  final String value;
  final String label;
}
