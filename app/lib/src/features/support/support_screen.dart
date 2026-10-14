import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/shop_branding.dart';
import '../../core/support/whatsapp_support.dart';
import '../../data/repositories/admin_repository.dart';

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  static const _faqs = <({String q, String a})>[
    (
      q: 'كيف أتابع طلبي بعد الإرسال؟',
      a: 'من صفحة "طلباتي" يمكنك متابعة الحالة بالكامل ومعرفة آخر تحديث.'
    ),
    (
      q: 'متى يظهر الخصم على المنتج؟',
      a: 'يظهر الخصم مباشرة على البطاقة وتفاصيل المنتج عندما يكون العرض فعالاً.'
    ),
    (
      q: 'لماذا لا أستطيع إضافة منتج للسلة؟',
      a: 'قد يكون المنتج غير متوفر حالياً أو الكمية أقل من الحد الأدنى للطلب.'
    ),
    (
      q: 'كيف أطلب فاتورة؟',
      a: 'افتح الطلب ثم اختر عرض الفاتورة أو تحميلها حسب المنصة المتاحة.'
    ),
  ];

  static const _topics = <({String key, String title, IconData icon})>[
    (key: 'order', title: 'الطلب', icon: Icons.receipt_long_outlined),
    (key: 'product', title: 'المنتج', icon: Icons.inventory_2_outlined),
    (key: 'account', title: 'الحساب', icon: Icons.person_outline),
    (key: 'delivery', title: 'التوصيل', icon: Icons.local_shipping_outlined),
    (key: 'other', title: 'أخرى', icon: Icons.help_outline),
  ];

  String _topicMessage({
    required String topic,
    required String shopName,
  }) {
    return 'مرحباً، أحتاج مساعدة بخصوص "$topic" في تطبيق $shopName.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).asData?.value;
    final shopName = ref.watch(shopBrandingProvider).shopName;
    final supportPhone = settings?.supportWhatsapp.trim().isNotEmpty == true
        ? settings!.supportWhatsapp
        : AppConfig.supportWhatsapp;
    final whatsappReady = WhatsAppSupport.isConfiguredFor(supportPhone);
    return Scaffold(
      appBar: AppBar(title: const Text('المساعدة والدعم')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تواصل مباشر عبر واتساب',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    whatsappReady
                        ? 'رقم الدعم: ${WhatsAppSupport.displayPhoneFor(supportPhone)}'
                        : 'رقم واتساب الدعم غير مهيأ حالياً.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final topic in _topics)
                FilledButton.tonalIcon(
                  key: Key('support-topic-${topic.key}'),
                  onPressed: !whatsappReady
                      ? null
                      : () async {
                          final opened = await WhatsAppSupport.openMessage(
                            _topicMessage(
                              topic: topic.title,
                              shopName: shopName,
                            ),
                            phone: supportPhone,
                          );
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تعذر فتح واتساب حالياً'),
                              ),
                            );
                          }
                        },
                  icon: Icon(topic.icon),
                  label: Text(topic.title),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'الأسئلة الشائعة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final faq in _faqs)
            Card(
              child: ExpansionTile(
                key: Key('support-faq-${faq.q}'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding:
                    const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 14),
                title: Text(faq.q),
                children: [Text(faq.a)],
              ),
            ),
        ],
      ),
    );
  }
}
