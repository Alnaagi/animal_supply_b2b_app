import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/support/invite_delivery.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/responsive_field_group.dart';
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
  final Set<String> busyCustomerIds = <String>{};
  List<BusinessCustomer> customers = const <BusinessCustomer>[];
  String? status;
  Object? loadError;
  bool loadingInitial = true;
  bool loadingMore = false;
  bool hasMore = false;
  int nextOffset = 0;
  int requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCustomers());
  }

  @override
  void dispose() {
    requestGeneration++;
    search.dispose();
    super.dispose();
  }

  Future<void> _refreshCustomers() async {
    if (!mounted) return;
    final generation = ++requestGeneration;
    setState(() {
      customers = const <BusinessCustomer>[];
      loadError = null;
      loadingInitial = true;
      loadingMore = false;
      hasMore = false;
      nextOffset = 0;
    });
    try {
      final page = await ref.read(adminRepositoryProvider).listCustomersPage(
            query: search.text,
            status: status,
            limit: adminCustomersDefaultPageSize,
          );
      if (!mounted || generation != requestGeneration) return;
      setState(() {
        customers = page.customers;
        nextOffset = page.nextOffset;
        hasMore = page.hasMore;
        loadingInitial = false;
      });
    } catch (error) {
      if (!mounted || generation != requestGeneration) return;
      setState(() {
        loadError = error;
        loadingInitial = false;
      });
    }
  }

  Future<void> _loadMoreCustomers() async {
    if (!mounted || loadingInitial || loadingMore || !hasMore) return;
    final generation = requestGeneration;
    setState(() => loadingMore = true);
    try {
      final page = await ref.read(adminRepositoryProvider).listCustomersPage(
            query: search.text,
            status: status,
            offset: nextOffset,
            limit: adminCustomersDefaultPageSize,
          );
      if (!mounted || generation != requestGeneration) return;
      final existingIds = customers.map((customer) => customer.id).toSet();
      setState(() {
        customers = <BusinessCustomer>[
          ...customers,
          for (final customer in page.customers)
            if (existingIds.add(customer.id)) customer,
        ];
        nextOffset = page.nextOffset;
        hasMore = page.hasMore;
        loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != requestGeneration) return;
      setState(() => loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحميل المزيد من العملاء. حاول مرة أخرى.'),
        ),
      );
    }
  }

  void _selectStatus(String? value) {
    if (status == value) return;
    setState(() => status = value);
    unawaited(_refreshCustomers());
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'إدارة العملاء',
      actions: [
        IconButton(
          onPressed:
              loadingInitial ? null : () => unawaited(_refreshCustomers()),
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث العملاء',
        ),
        IconButton(
            onPressed: _showCreateCustomer,
            icon: const Icon(Icons.person_add),
            tooltip: 'عميل جديد'),
      ],
      child: loadingInitial
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
              ? _CustomerLoadError(
                  onRetry: () => unawaited(_refreshCustomers()),
                )
              : RefreshIndicator(
                  onRefresh: _refreshCustomers,
                  child: ListView(
                    key: const Key('admin-customers-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
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
                                    labelText:
                                        'بحث باسم النشاط أو الهاتف أو المدينة'),
                                maxLength: 120,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) =>
                                    unawaited(_refreshCustomers()),
                              ),
                            ),
                            ChoiceChip(
                                label: const Text('الكل'),
                                selected: status == null,
                                onSelected: (_) => _selectStatus(null)),
                            ChoiceChip(
                                label: const Text('نشط'),
                                selected: status == 'active',
                                onSelected: (_) => _selectStatus('active')),
                            ChoiceChip(
                                label: const Text('موقوف'),
                                selected: status == 'suspended',
                                onSelected: (_) => _selectStatus('suspended')),
                            ChoiceChip(
                                label: const Text('مؤرشف'),
                                selected: status == 'archived',
                                onSelected: (_) => _selectStatus('archived')),
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
                              onTap: busyCustomerIds.contains(customer.id)
                                  ? null
                                  : () => unawaited(
                                        _handleCustomerAction(
                                          'edit',
                                          customer,
                                        ),
                                      ),
                              leading: CircleAvatar(
                                  backgroundColor:
                                      customer.accountStatus == 'archived'
                                          ? Colors.grey
                                          : customer.active
                                              ? AppTheme.green
                                              : AppTheme.red,
                                  child: Icon(
                                      customer.accountStatus == 'archived'
                                          ? Icons.archive_outlined
                                          : customer.active
                                              ? Icons.store
                                              : Icons.block,
                                      color: Colors.white)),
                              title: Text(customer.businessName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                              subtitle: Text(
                                [
                                  if (customer.contactPerson.trim().isNotEmpty)
                                    customer.contactPerson.trim(),
                                  customer.username,
                                  if (customer.phone.trim().isNotEmpty)
                                    customer.phoneIsWhatsapp
                                        ? 'واتساب ${customer.phone}'
                                        : customer.phone,
                                  '${customer.city} ${customer.area}'.trim(),
                                  'خصم ${_formatDiscountPercent(customer.discountPercent)}',
                                ].where((part) => part.isNotEmpty).join(' • '),
                                key: ValueKey(
                                  'admin-customer-discount-${customer.id}',
                                ),
                              ),
                              isThreeLine: true,
                              trailing: busyCustomerIds.contains(customer.id)
                                  ? const SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : PopupMenuButton<String>(
                                      key: ValueKey(
                                        'admin-customer-menu-${customer.id}',
                                      ),
                                      onSelected: (value) =>
                                          _handleCustomerAction(
                                              value, customer),
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('تعديل')),
                                        if (customer.accountStatus ==
                                            'archived')
                                          const PopupMenuItem(
                                            value: 'restore',
                                            child: Text('استعادة العميل'),
                                          )
                                        else ...[
                                          PopupMenuItem(
                                              value: 'toggle',
                                              child: Text(customer.active
                                                  ? 'إيقاف العميل'
                                                  : 'تفعيل العميل')),
                                          const PopupMenuItem(
                                              value: 'reset',
                                              child: Text(
                                                  'كلمة مرور ودعوة جديدة عبر واتساب')),
                                          const PopupMenuDivider(),
                                          const PopupMenuItem(
                                            value: 'archive',
                                            child: Text('أرشفة العميل'),
                                          ),
                                        ],
                                      ],
                                    ),
                            ),
                          ),
                      if (customers.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Center(
                          child: Text(
                            'تم عرض ${customers.length} من العملاء',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (hasMore || loadingMore) ...[
                        const SizedBox(height: 12),
                        Center(
                          child: FilledButton.tonalIcon(
                            key: const Key('admin-customers-load-more'),
                            onPressed: loadingMore
                                ? null
                                : () => unawaited(_loadMoreCustomers()),
                            icon: loadingMore
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.expand_more),
                            label: Text(
                              loadingMore
                                  ? 'جارٍ تحميل المزيد...'
                                  : 'تحميل المزيد',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Future<void> _handleCustomerAction(
      String action, BusinessCustomer customer) async {
    final repo = ref.read(adminRepositoryProvider);
    if (action == 'edit') return _showCustomerForm(customer);
    if (action == 'restore') {
      final confirmed = await _confirmCustomerAction(
        title: 'استعادة العميل',
        message:
            'سيعود «${customer.businessName}» إلى قائمة العملاء النشطين ويمكنه تسجيل الدخول والطلب.',
        confirmLabel: 'استعادة وتفعيل',
      );
      if (!confirmed) return;
      await _runCustomerAction(customer.id, () async {
        await repo.saveCustomer(customer.copyWith(accountStatus: 'active'));
        if (mounted) await _refreshCustomers();
      });
      return;
    }
    if (action == 'archive') {
      final confirmed = await _confirmCustomerAction(
        title: 'تأكيد أرشفة العميل',
        message:
            'سيتم تعطيل حساب «${customer.businessName}» وإخفاؤه من القوائم التشغيلية. تبقى طلباته وسجلاته محفوظة ويمكن استعادته لاحقاً.',
        confirmLabel: 'أرشفة الحساب',
      );
      if (!confirmed) return;
      await _runCustomerAction(customer.id, () async {
        await repo.saveCustomer(customer.copyWith(accountStatus: 'archived'));
        if (mounted) await _refreshCustomers();
      });
      return;
    }
    if (action == 'toggle') {
      if (customer.active) {
        final confirmed = await _confirmCustomerAction(
          title: 'تأكيد إيقاف العميل',
          message:
              'لن يتمكن «${customer.businessName}» من تسجيل الطلبات حتى إعادة تفعيل الحساب.',
          confirmLabel: 'إيقاف الحساب',
        );
        if (!confirmed) return;
      }
      await _runCustomerAction(customer.id, () async {
        await repo.saveCustomer(customer.copyWith(
            accountStatus: customer.active ? 'suspended' : 'active'));
        if (mounted) await _refreshCustomers();
      });
      return;
    }
    if (action == 'reset') {
      final confirmed = await _confirmCustomerAction(
        title: 'تأكيد إنشاء بيانات دخول جديدة',
        message:
            'سيتم تغيير كلمة مرور «${customer.businessName}» وإلغاء الدعوة السابقة. '
            'لا تنفذ هذه العملية إلا إذا كان العميل مستعداً لاستلام الرابط الجديد.',
        confirmLabel: 'إنشاء دعوة جديدة',
      );
      if (!confirmed) return;
      await _runCustomerAction(customer.id, () async {
        final result = await repo.resetCustomerPassword(customer);
        if (mounted) _showInviteResult(result);
      });
      return;
    }
  }

  Future<bool> _confirmCustomerAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runCustomerAction(
    String customerId,
    Future<void> Function() action,
  ) async {
    if (busyCustomerIds.contains(customerId)) return;
    setState(() => busyCustomerIds.add(customerId));
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إكمال العملية. تحقق من الاتصال وحاول مجدداً.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busyCustomerIds.remove(customerId));
    }
  }

  void _showCreateCustomer() => _showCustomerForm(const BusinessCustomer(
      id: 'new', businessName: '', username: '', city: 'طرابلس', area: ''));

  Future<void> _showCustomerForm(BusinessCustomer customer) async {
    final isNew = customer.id == 'new';
    final business = TextEditingController(text: customer.businessName);
    final username = TextEditingController(text: customer.username);
    final contact = TextEditingController(text: customer.contactPerson);
    final phone = TextEditingController(text: customer.phone);
    final city = TextEditingController(text: customer.city);
    final area = TextEditingController(text: customer.area);
    final address = TextEditingController(text: customer.address);
    final password = TextEditingController();
    final passwordConfirm = TextEditingController();
    final credit =
        TextEditingController(text: customer.creditLimit.toStringAsFixed(0));
    final outstanding = TextEditingController(
        text: customer.outstandingBalance.toStringAsFixed(0));
    final discount = TextEditingController(
      text: _formatDiscountNumber(customer.discountPercent),
    );
    var statusValue = customer.accountStatus;
    var phoneIsWhatsapp = customer.phoneIsWhatsapp;
    var obscurePassword = true;
    String? validationMessage;

    final saved = await showDialog<_CustomerFormResult>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
              title: Text(isNew ? 'إنشاء عميل' : 'تعديل عميل'),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (AppConfig.isDemoMode) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.orange.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'وضع تجريبي محلي: لا يُنشأ حساب حقيقي في الخادم، '
                            'ولا تُحفظ كلمة المرور على الجهاز.',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        key: const ValueKey('admin-customer-contact-field'),
                        controller: contact,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'الشخص المسؤول',
                          helperText: 'الاسم واللقب',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('admin-customer-business-field'),
                        controller: business,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'اسم النشاط التجاري',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('admin-customer-phone-field'),
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: phoneIsWhatsapp
                              ? 'رقم الهاتف (واتساب)'
                              : 'رقم الهاتف',
                          prefixIcon: Icon(
                            phoneIsWhatsapp
                                ? Icons.chat_outlined
                                : Icons.phone_outlined,
                          ),
                        ),
                      ),
                      CheckboxListTile(
                        key: const ValueKey(
                          'admin-customer-whatsapp-preferred',
                        ),
                        value: phoneIsWhatsapp,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('هذا الرقم لواتساب (مفضّل)'),
                        subtitle: const Text(
                          'يُستخدم للتواصل والدعوات عبر واتساب.',
                        ),
                        onChanged: (value) => setDialogState(
                          () => phoneIsWhatsapp = value ?? true,
                        ),
                      ),
                      ResponsiveFieldGroup(children: [
                        TextField(
                          controller: city,
                          textInputAction: TextInputAction.next,
                          decoration:
                              const InputDecoration(labelText: 'المدينة'),
                        ),
                        TextField(
                          controller: area,
                          textInputAction: TextInputAction.next,
                          decoration:
                              const InputDecoration(labelText: 'المنطقة'),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                        controller: username,
                        enabled: isNew,
                        textDirection: TextDirection.ltr,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'اسم المستخدم',
                          helperText: isNew
                              ? '3-64 حرفاً لاتينياً أو رقماً، ويمكن استخدام . _ -'
                              : 'لا يمكن تغيير اسم المستخدم بعد الإنشاء',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('admin-customer-password-field'),
                        controller: password,
                        obscureText: obscurePassword,
                        textDirection: TextDirection.ltr,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: isNew ? 'كلمة المرور' : 'كلمة مرور جديدة',
                          helperText: isNew
                              ? 'اختياري. إن تُركت فارغة يولّد الخادم كلمة مرور مؤقتة. لا تُوضع في الرابط.'
                              : 'اتركه فارغاً للإبقاء على كلمة المرور الحالية. تُحفظ في الخادم فقط.',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setDialogState(
                              () => obscurePassword = !obscurePassword,
                            ),
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey(
                          'admin-customer-password-confirm-field',
                        ),
                        controller: passwordConfirm,
                        obscureText: obscurePassword,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'تأكيد كلمة المرور',
                          helperText: 'مطلوب فقط عند إدخال كلمة مرور.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('admin-customer-discount-field'),
                        controller: discount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textDirection: TextDirection.ltr,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9٠-٩۰-۹.,٫،]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'خصم العميل',
                          helperText:
                              'يُطبّق تلقائياً على السعر الأساسي. اكتب 0 لعدم تطبيق خصم.',
                          suffixText: '%',
                          prefixIcon: Icon(Icons.percent),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        key: const ValueKey(
                          'admin-customer-secondary-fields',
                        ),
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'عنوان وائتمان مرجعي',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'حقول محاسبية وعنوان تفصيلي؛ ليست أساسية للطلب.',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: address,
                                decoration:
                                    const InputDecoration(labelText: 'العنوان'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: credit,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'حد الائتمان المرجعي',
                                  helperText:
                                      'للمتابعة اليدوية فقط؛ لا يمنع الطلبات تلقائياً.',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: outstanding,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'الرصيد المستحق المسجل يدوياً',
                                  helperText:
                                      'قيمة مرجعية فقط؛ لا تُنشئ فاتورة أو دفعة تلقائياً.',
                                ),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: statusValue,
                                decoration:
                                    const InputDecoration(labelText: 'الحالة'),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'active', child: Text('نشط')),
                                  DropdownMenuItem(
                                      value: 'suspended',
                                      child: Text('موقوف')),
                                  DropdownMenuItem(
                                      value: 'archived', child: Text('مؤرشف')),
                                ],
                                onChanged: (value) => setDialogState(
                                  () => statusValue = value ?? 'active',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          validationMessage!,
                          key: const ValueKey('admin-customer-form-validation'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء')),
                FilledButton(
                  onPressed: () {
                    final parsedCredit = double.tryParse(credit.text.trim());
                    final parsedOutstanding =
                        double.tryParse(outstanding.text.trim());
                    final parsedDiscount =
                        _parseCustomerDiscountPercent(discount.text);
                    final nextPassword = password.text.trim();
                    if (parsedDiscount == null) {
                      setDialogState(() {
                        validationMessage =
                            'نسبة الخصم يجب أن تكون بين 0 و99.99 وبحد أقصى منزلتين عشريتين.';
                      });
                      return;
                    }
                    if (contact.text.trim().isEmpty ||
                        business.text.trim().isEmpty ||
                        username.text.trim().isEmpty ||
                        phone.text.trim().isEmpty ||
                        city.text.trim().isEmpty ||
                        parsedCredit == null ||
                        !parsedCredit.isFinite ||
                        parsedCredit < 0 ||
                        parsedOutstanding == null ||
                        !parsedOutstanding.isFinite ||
                        parsedOutstanding < 0) {
                      setDialogState(() {
                        validationMessage =
                            'أدخل الشخص المسؤول واسم النشاط والهاتف والمدينة واسم المستخدم، مع حد ائتمان ورصيد غير سالبين.';
                      });
                      return;
                    }
                    if (nextPassword.isNotEmpty ||
                        passwordConfirm.text.trim().isNotEmpty) {
                      final passwordError = _adminCustomerPasswordError(
                        nextPassword,
                        passwordConfirm.text,
                      );
                      if (passwordError != null) {
                        setDialogState(() => validationMessage = passwordError);
                        return;
                      }
                    }
                    Navigator.pop(
                      context,
                      _CustomerFormResult(
                        customer: customer.copyWith(
                          businessName: business.text.trim(),
                          username: username.text.trim(),
                          contactPerson: contact.text.trim(),
                          phone: phone.text.trim(),
                          phoneIsWhatsapp: phoneIsWhatsapp,
                          city: city.text.trim(),
                          area: area.text.trim(),
                          address: address.text.trim(),
                          creditLimit: parsedCredit,
                          outstandingBalance: parsedOutstanding,
                          discountPercent: parsedDiscount,
                          accountStatus: statusValue,
                        ),
                        password: nextPassword,
                      ),
                    );
                  },
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ),
        ),
      );
    if (saved == null) return;
    await _runCustomerAction(saved.customer.id, () async {
      final repo = ref.read(adminRepositoryProvider);
      if (saved.customer.id == 'new') {
        final result = await repo.createCustomerInvite(
          saved.customer,
          password: saved.password.isEmpty ? null : saved.password,
        );
        if (mounted) _showInviteResult(result);
      } else {
        await repo.saveCustomer(saved.customer);
        if (saved.password.isNotEmpty) {
          await repo.setCustomerPassword(
            saved.customer,
            password: saved.password,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppConfig.isDemoMode
                      ? 'وضع تجريبي: لم تُحدَّث كلمة المرور في الخادم.'
                      : 'تم تعيين كلمة المرور في الخادم. لن تُرسل داخل الرابط أو الدعوة.',
                ),
              ),
            );
          }
        }
      }
      if (mounted) await _refreshCustomers();
    });
  }

  void _showInviteResult(InviteResult result) {
    final isDemo = AppConfig.isDemoMode;
    final normalizedPhone = _normalizeLibyanWhatsapp(result.customerPhone);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isDemo ? 'حساب تجريبي محلي' : 'رسالة واتساب آمنة',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDemo)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.orange.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'هذه نسخة تجريبية: لم يتم إنشاء مستخدم حقيقي أو تغيير كلمة مرور في الخادم. بيانات الدعوة الوهمية غير صالحة ولا يجب إرسالها إلى عميل.',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  )
                else if (normalizedPhone == null)
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
                      Expanded(
                        child: Text(
                          'سيتم نسخ الرسالة ثم فتح واتساب على الرقم: '
                          '$normalizedPhone. الصق الرسالة داخل المحادثة.',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ]),
                  ),
                if (!isDemo) SelectableText(result.whatsappMessage),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق')),
          if (!isDemo) ...[
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
              label: const Text('نسخ وفتح واتساب'),
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
    await Clipboard.setData(ClipboardData(text: message));
    final url = inviteWhatsappContactUri(phone);
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!dialogContext.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'تم نسخ الرسالة. الصقها داخل محادثة واتساب.'
              : 'تعذر فتح واتساب، لكن تم نسخ الرسالة.',
        ),
      ),
    );
  }
}

class _CustomerFormResult {
  const _CustomerFormResult({
    required this.customer,
    required this.password,
  });

  final BusinessCustomer customer;
  final String password;
}

String? _adminCustomerPasswordError(String password, String confirmation) {
  if (password != confirmation.trim()) {
    return 'كلمتا المرور غير متطابقتين.';
  }
  if (password.length < 10) {
    return 'استخدم كلمة مرور من 10 أحرف على الأقل.';
  }
  if (password.length > 128) {
    return 'يجب ألا تتجاوز كلمة المرور 128 حرفاً.';
  }
  if (!RegExp('[A-Z]').hasMatch(password) ||
      !RegExp('[a-z]').hasMatch(password) ||
      !RegExp('[0-9]').hasMatch(password) ||
      !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
    return 'يجب أن تحتوي كلمة المرور على حرف إنجليزي كبير وصغير ورقم ورمز.';
  }
  return null;
}

String _formatDiscountNumber(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _formatDiscountPercent(double value) =>
    '${_formatDiscountNumber(value)}%';

double? _parseCustomerDiscountPercent(String value) {
  final normalized = _normalizeLocalizedNumber(value);
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parsed = double.tryParse(normalized);
  if (parsed == null) return null;
  try {
    return validatedCustomerDiscountPercent(parsed);
  } on ArgumentError {
    return null;
  }
}

String _normalizeLocalizedNumber(String value) {
  const easternArabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  const westernDigits = '0123456789';
  final buffer = StringBuffer();
  for (final rune in value.trim().runes) {
    final character = String.fromCharCode(rune);
    final easternIndex = easternArabicDigits.indexOf(character);
    final persianIndex = persianDigits.indexOf(character);
    if (easternIndex >= 0) {
      buffer.write(westernDigits[easternIndex]);
    } else if (persianIndex >= 0) {
      buffer.write(westernDigits[persianIndex]);
    } else if (character == '٫' || character == '،' || character == ',') {
      buffer.write('.');
    } else {
      buffer.write(character);
    }
  }
  return buffer.toString();
}

class _CustomerLoadError extends StatelessWidget {
  const _CustomerLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 52),
            const SizedBox(height: 12),
            Text(
              'تعذر تحميل العملاء',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text('تحقق من الاتصال ثم أعد المحاولة.'),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
