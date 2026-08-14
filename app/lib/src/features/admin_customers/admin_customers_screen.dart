import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';
import '../admin_dashboard/admin_shell.dart';

class AdminCustomersScreen extends ConsumerStatefulWidget {
  const AdminCustomersScreen({super.key});

  @override
  ConsumerState<AdminCustomersScreen> createState() =>
      _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends ConsumerState<AdminCustomersScreen> {
  final search = TextEditingController();
  String? status;
  int refreshKey = 0;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'إدارة العملاء',
      actions: [
        IconButton(
            onPressed: _showCreateCustomer,
            icon: const Icon(Icons.person_add),
            tooltip: 'عميل جديد'),
      ],
      child: FutureBuilder<List<BusinessCustomer>>(
        key: ValueKey(refreshKey),
        future: ref
            .read(adminRepositoryProvider)
            .listCustomers(query: search.text, status: status),
        builder: (context, snapshot) {
          final customers = snapshot.data ?? const <BusinessCustomer>[];
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 360,
                      child: TextField(
                        controller: search,
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'بحث باسم النشاط أو الهاتف أو المدينة'),
                        onSubmitted: (_) => setState(() => refreshKey++),
                      ),
                    ),
                    ChoiceChip(
                        label: const Text('الكل'),
                        selected: status == null,
                        onSelected: (_) => setState(() => status = null)),
                    ChoiceChip(
                        label: const Text('نشط'),
                        selected: status == 'active',
                        onSelected: (_) => setState(() => status = 'active')),
                    ChoiceChip(
                        label: const Text('موقوف'),
                        selected: status == 'suspended',
                        onSelected: (_) =>
                            setState(() => status = 'suspended')),
                    FilledButton.icon(
                        onPressed: _showCreateCustomer,
                        icon: const Icon(Icons.add),
                        label: const Text('إنشاء عميل')),
                  ]),
              const SizedBox(height: 14),
              if (customers.isEmpty)
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.groups_outlined),
                        title: Text('لا يوجد عملاء بهذا البحث')))
              else
                for (final customer in customers)
                  Card(
                    key: ValueKey(
                      'admin-customer-card-${customer.id}',
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      onTap: () => _showCustomerForm(customer),
                      leading: CircleAvatar(
                          backgroundColor:
                              customer.active ? AppTheme.green : AppTheme.red,
                          child: Icon(
                              customer.active ? Icons.store : Icons.block,
                              color: Colors.white)),
                      title: Text(customer.businessName,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(
                          '${customer.username} • ${customer.city} ${customer.area} • ${customer.priceGroup}\nرصيد: ${lyd(customer.outstandingBalance)} • حد ائتمان: ${lyd(customer.creditLimit)}'),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        key: ValueKey(
                          'admin-customer-menu-${customer.id}',
                        ),
                        onSelected: (value) =>
                            _handleCustomerAction(value, customer),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('تعديل')),
                          PopupMenuItem(
                              value: 'toggle',
                              child: Text(customer.active
                                  ? 'إيقاف العميل'
                                  : 'تفعيل العميل')),
                          const PopupMenuItem(
                              value: 'reset',
                              child: Text('إعادة تعيين كلمة المرور')),
                          const PopupMenuItem(
                              value: 'invite',
                              child: Text('توليد رسالة واتساب')),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleCustomerAction(
      String action, BusinessCustomer customer) async {
    final repo = ref.read(adminRepositoryProvider);
    if (action == 'edit') return _showCustomerForm(customer);
    if (action == 'toggle') {
      await repo.saveCustomer(customer.copyWith(
          accountStatus: customer.active ? 'suspended' : 'active'));
      setState(() => refreshKey++);
      return;
    }
    if (action == 'reset') {
      final result = await repo.resetCustomerPassword(customer);
      if (mounted) _showInviteResult(result);
      return;
    }
    if (action == 'invite') {
      final result = await repo.createCustomerInvite(customer);
      if (mounted) _showInviteResult(result);
    }
  }

  void _showCreateCustomer() => _showCustomerForm(const BusinessCustomer(
      id: 'new', businessName: '', username: '', city: 'طرابلس', area: ''));

  Future<void> _showCustomerForm(BusinessCustomer customer) async {
    final business = TextEditingController(text: customer.businessName);
    final username = TextEditingController(text: customer.username);
    final contact = TextEditingController(text: customer.contactPerson);
    final phone = TextEditingController(text: customer.phone);
    final city = TextEditingController(text: customer.city);
    final area = TextEditingController(text: customer.area);
    final address = TextEditingController(text: customer.address);
    final credit =
        TextEditingController(text: customer.creditLimit.toStringAsFixed(0));
    var statusValue = customer.accountStatus;

    final saved = await showDialog<BusinessCustomer>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(customer.id == 'new' ? 'إنشاء عميل' : 'تعديل عميل'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(children: [
                TextField(
                    controller: business,
                    decoration:
                        const InputDecoration(labelText: 'اسم النشاط التجاري')),
                const SizedBox(height: 10),
                TextField(
                    controller: username,
                    decoration: const InputDecoration(
                        labelText: 'اسم المستخدم / البريد / الهاتف')),
                const SizedBox(height: 10),
                TextField(
                    controller: contact,
                    decoration:
                        const InputDecoration(labelText: 'الشخص المسؤول')),
                const SizedBox(height: 10),
                TextField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: 'الهاتف')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: city,
                          decoration:
                              const InputDecoration(labelText: 'المدينة'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: area,
                          decoration:
                              const InputDecoration(labelText: 'المنطقة'))),
                ]),
                const SizedBox(height: 10),
                TextField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'العنوان')),
                const SizedBox(height: 10),
                TextField(
                    controller: credit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'حد الائتمان placeholder')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: statusValue,
                  decoration: const InputDecoration(labelText: 'الحالة'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('نشط')),
                    DropdownMenuItem(value: 'suspended', child: Text('موقوف')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => statusValue = value ?? 'active'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                if (business.text.trim().isEmpty ||
                    username.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(
                  context,
                  customer.copyWith(
                    businessName: business.text.trim(),
                    username: username.text.trim(),
                    contactPerson: contact.text.trim(),
                    phone: phone.text.trim(),
                    city: city.text.trim(),
                    area: area.text.trim(),
                    address: address.text.trim(),
                    creditLimit: double.tryParse(credit.text) ?? 0,
                    accountStatus: statusValue,
                  ),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    business.dispose();
    username.dispose();
    contact.dispose();
    phone.dispose();
    city.dispose();
    area.dispose();
    address.dispose();
    credit.dispose();

    if (saved == null) return;
    if (saved.id == 'new') {
      final result =
          await ref.read(adminRepositoryProvider).createCustomerInvite(saved);
      if (mounted) _showInviteResult(result);
    } else {
      await ref.read(adminRepositoryProvider).saveCustomer(saved);
    }
    setState(() => refreshKey++);
  }

  void _showInviteResult(InviteResult result) {
    final normalizedPhone = _normalizeLibyanWhatsapp(result.customerPhone);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رسالة واتساب آمنة'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (normalizedPhone == null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.orange.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'رقم واتساب العميل غير صحيح. صحح الرقم من بيانات العميل ثم أرسل الدعوة، أو انسخ الرسالة يدوياً.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      const Icon(Icons.phone_android, color: AppTheme.green),
                      const SizedBox(width: 8),
                      Text('سيتم فتح واتساب على الرقم: $normalizedPhone',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                SelectableText(result.whatsappMessage),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق')),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xff25d366)),
            onPressed: normalizedPhone == null
                ? null
                : () => _openInviteWhatsapp(
                      context,
                      phone: normalizedPhone,
                      message: result.whatsappMessage,
                    ),
            icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 18),
            label: const Text('إرسال واتساب'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: result.whatsappMessage));
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ الرسالة'),
          ),
        ],
      ),
    );
  }

  String? _normalizeLibyanWhatsapp(String rawPhone) {
    var digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = '218${digits.substring(1)}';
    if (digits.startsWith('9')) digits = '218$digits';
    if (!digits.startsWith('2189')) return null;
    if (digits.length < 12 || digits.length > 13) return null;
    return digits;
  }

  Future<void> _openInviteWhatsapp(
    BuildContext dialogContext, {
    required String phone,
    required String message,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final url =
        Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: message));
    if (!dialogContext.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('تعذر فتح واتساب. تم نسخ الرسالة.')),
    );
  }
}
