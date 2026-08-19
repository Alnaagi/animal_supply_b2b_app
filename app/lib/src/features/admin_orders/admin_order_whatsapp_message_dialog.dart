import 'package:flutter/material.dart';

import '../../core/support/order_whatsapp_copy.dart';

class OrderWhatsappTemplateDialog extends StatefulWidget {
  const OrderWhatsappTemplateDialog({
    required this.initialTemplate,
    super.key,
  });

  final String initialTemplate;

  @override
  State<OrderWhatsappTemplateDialog> createState() =>
      _OrderWhatsappTemplateDialogState();
}

class _OrderWhatsappTemplateDialogState
    extends State<OrderWhatsappTemplateDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTemplate);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('قالب رسائل واتساب للطلبات'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'هذا القالب يجهّز رسالة كل طلب عند الضغط على واتساب أو نسخ الملخص، '
                  'ما لم تُحفظ رسالة خاصة لذلك الطلب. يُحفظ على هذا الجهاز فقط.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'العناصر النائبة: ${orderWhatsappTemplatePlaceholders.join('  ')}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12),
                ),
                const SizedBox(height: 6),
                const Text(
                  '{shop_name} اسم متجركم، و{store_name} أو {business_name} اسم متجر العميل. '
                  'رابط الفاتورة يظهر فقط إن وُجد، ولا تضعوا كلمات مرور في الروابط.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('admin-order-whatsapp-template-field'),
                  controller: _controller,
                  minLines: 10,
                  maxLines: 18,
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    labelText: 'نص القالب',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          OutlinedButton(
            onPressed: () => setState(() {
              _controller.text = defaultOrderWhatsappTemplate;
            }),
            child: const Text('استعادة الافتراضي'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('حفظ للطلبات'),
          ),
        ],
      ),
    );
  }
}

class OrderWhatsappOverrideDialog extends StatefulWidget {
  const OrderWhatsappOverrideDialog({
    required this.orderLabel,
    required this.initialMessage,
    required this.defaultMessage,
    super.key,
  });

  final String orderLabel;
  final String initialMessage;
  final String defaultMessage;

  @override
  State<OrderWhatsappOverrideDialog> createState() =>
      _OrderWhatsappOverrideDialogState();
}

class _OrderWhatsappOverrideDialogState
    extends State<OrderWhatsappOverrideDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMessage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('رسالة واتساب للطلب ${widget.orderLabel}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'يُستخدم هذا النص عند إرسال واتساب أو نسخ الملخص لهذا الطلب فقط. '
                  'يُحفظ على هذا الجهاز.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('admin-order-whatsapp-override-field'),
                  controller: _controller,
                  minLines: 10,
                  maxLines: 18,
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    labelText: 'نص الرسالة',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          OutlinedButton(
            key: const ValueKey('admin-order-whatsapp-override-reset'),
            onPressed: () => setState(() {
              _controller.text = widget.defaultMessage;
            }),
            child: const Text('استعادة الافتراضي'),
          ),
          FilledButton(
            key: const ValueKey('admin-order-whatsapp-override-save'),
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('حفظ لهذه الرسالة'),
          ),
        ],
      ),
    );
  }
}
