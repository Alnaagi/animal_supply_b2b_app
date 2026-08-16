import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/login_identifier.dart';
import '../../core/config/app_config.dart';
import '../../core/refresh/screen_reload.dart';
import '../../core/support/customer_invite_copy.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shop_loading.dart';
import '../../core/widgets/shop_refresh_indicator.dart';
import '../../data/local/customer_invite_template_store.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';
import '../admin_dashboard/admin_shell.dart';
import 'whatsapp_invite_dialog.dart';

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
  final Map<String, String> _sessionKnownPasswords = <String, String>{};
  String? _menuTapGuardCustomerId;
  bool _customerFormOpen = false;

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

  Future<void> _refreshCustomers({bool keepResults = false}) async {
    if (!mounted) return;
    final generation = ++requestGeneration;
    setState(() {
      if (!keepResults) {
        customers = const <BusinessCustomer>[];
        loadingInitial = true;
      }
      loadError = null;
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
    listenForScreenReload(
      ref,
      () => _refreshCustomers(keepResults: customers.isNotEmpty),
    );
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
          key: const Key('admin-customers-invite-template-gear'),
          onPressed: () => unawaited(_showInviteTemplateSettings()),
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'نص دعوة واتساب',
        ),
        IconButton(
            onPressed: _showCreateCustomer,
            icon: const Icon(Icons.person_add),
            tooltip: 'عميل جديد'),
      ],
      child: loadingInitial
          ? const ShopLoading.page()
          : loadError != null
              ? _CustomerLoadError(
                  onRetry: () => unawaited(_refreshCustomers()),
                )
              : ShopRefreshIndicator(
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
                                        'بحث باسم المتجر أو الهاتف أو المدينة'),
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
                                  : () {
                                      if (_customerFormOpen ||
                                          _menuTapGuardCustomerId ==
                                          customer.id) {
                                        _menuTapGuardCustomerId = null;
                                        return;
                                      }
                                      unawaited(
                                        _handleCustomerAction(
                                          'edit',
                                          customer,
                                        ),
                                      );
                                    },
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
                                      onSelected: (value) {
                                      _menuTapGuardCustomerId = customer.id;
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (!mounted) return;
                                        unawaited(
                                          _handleCustomerAction(
                                            value,
                                            customer,
                                          ),
                                        );
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (_menuTapGuardCustomerId ==
                                              customer.id) {
                                            _menuTapGuardCustomerId = null;
                                          }
                                        });
                                      });
                                    },
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
                                              key: ValueKey(
                                                'admin-customer-toggle-${customer.id}',
                                              ),
                                              value: 'toggle',
                                              child: Text(customer.active
                                                  ? 'إيقاف العميل'
                                                  : 'تفعيل العميل')),
                                          const PopupMenuItem(
                                              value: 'share-login',
                                              child: Text(
                                                  'رسالة ترحيب ورابط الدخول عبر واتساب')),
                                          const PopupMenuDivider(),
                                          const PopupMenuItem(
                                            key: ValueKey(
                                              'admin-customer-archive-action',
                                            ),
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
                                ? const ShopLoading.compact()
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
        if (mounted) {
          await reloadAfterMutation(
            this,
            () => _refreshCustomers(keepResults: true),
          );
        }
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
        if (mounted) {
          await reloadAfterMutation(
            this,
            () => _refreshCustomers(keepResults: true),
          );
        }
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
        if (mounted) {
          await reloadAfterMutation(
            this,
            () => _refreshCustomers(keepResults: true),
          );
        }
      });
      return;
    }
    if (action == 'share-login') {
      final confirmed = await _confirmCustomerAction(
        title: 'إرسال رسالة الدخول',
        message:
            'سيتم تجهيز رسالة ترحيب ورابط تسجيل الدخول لـ «${customer.businessName}». '
            'لن تتغير كلمة المرور الحالية ولن تُلغى الدعوة السابقة، إلا إذا عدّلتم كلمة المرور من القلم داخل النافذة واخترتم حفظها في الخادم.',
        confirmLabel: 'تجهيز الرسالة',
      );
      if (!confirmed) return;
      InviteResult? result;
      await _runCustomerAction(customer.id, () async {
        final template = await ref
            .read(customerInviteTemplateStoreProvider)
            .load();
        result = repo.composeLoginReminder(
          customer,
          knownPassword: _knownPasswordFor(customer),
          inviteTemplate: template,
        );
      });
      if (mounted && result != null) {
        await _showInviteResult(result!, customer: customer);
      }
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_customerActionErrorAr(error))),
        );
        final code =
            AdminRepository.describeRemoteError(error).code.toUpperCase();
        if (code == 'STALE_WRITE' || code == 'CUSTOMER_UPDATE_CONFLICT') {
          await _refreshCustomers(keepResults: true);
        }
      }
    } finally {
      if (mounted) setState(() => busyCustomerIds.remove(customerId));
    }
  }

  void _showCreateCustomer() => _showCustomerForm(const BusinessCustomer(
      id: 'new', businessName: '', username: '', city: 'طرابلس', area: ''));

  Future<void> _showCustomerForm(BusinessCustomer customer) async {
    if (_customerFormOpen) return;
    _customerFormOpen = true;
    try {
      await _presentCustomerForm(customer);
    } finally {
      if (mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      _customerFormOpen = false;
    }
  }

  Future<void> _presentCustomerForm(BusinessCustomer customer) async {
    final isNew = customer.id == 'new';
    final business = TextEditingController(text: customer.businessName);
    final username = TextEditingController(text: customer.username);
    final contact = TextEditingController(text: customer.contactPerson);
    final phone = TextEditingController(text: customer.phone);
    final city = TextEditingController(text: customer.city);
    final area = TextEditingController(text: customer.area);
    final password = TextEditingController();
    final passwordConfirm = TextEditingController();
    final discount = TextEditingController(
      text: _formatDiscountNumber(customer.discountPercent),
    );
    var statusValue = customer.accountStatus;
    var obscurePassword = true;
    String? validationMessage;

    final saved = await showDialog<_CustomerFormResult>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final dialogMaxHeight =
                MediaQuery.sizeOf(context).height * 0.72;
            return AlertDialog(
              title: Text(isNew ? 'إنشاء عميل' : 'تعديل عميل'),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              content: SizedBox(
                width: 560,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: dialogMaxHeight),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (AppConfig.isDemoMode) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.orange.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'وضع تجريبي محلي: لا يُنشأ حساب حقيقي في الخادم، '
                            'ولا تُحفظ كلمة المرور على الجهاز.',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _CustomerFormSection(
                        key: const ValueKey('admin-customer-section-identity'),
                        title: 'الهوية',
                        icon: Icons.storefront_outlined,
                        children: [
                          TextField(
                            key: const ValueKey(
                              'admin-customer-business-field',
                            ),
                            controller: business,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'اسم المتجر',
                              helperText: 'الاسم الظاهر في الطلبات والدعوة',
                              prefixIcon: Icon(Icons.storefront_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const ValueKey(
                              'admin-customer-contact-field',
                            ),
                            controller: contact,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'الشخص المسؤول',
                              helperText: 'الاسم واللقب',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _CustomerFormSection(
                        key: const ValueKey('admin-customer-section-contact'),
                        title: 'التواصل',
                        icon: Icons.chat_outlined,
                        children: [
                          TextField(
                            key: const ValueKey(
                              'admin-customer-phone-field',
                            ),
                            controller: phone,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'رقم الهاتف (واتساب)',
                              helperText:
                                  'يمكن استخدام الرقم كاسم مستخدم عند الإنشاء',
                              helperMaxLines: 2,
                              prefixIcon: Icon(Icons.chat_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: city,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'المدينة',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: area,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'المنطقة',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _CustomerFormSection(
                        key: const ValueKey('admin-customer-section-login'),
                        title: 'بيانات الدخول',
                        icon: Icons.lock_outline,
                        children: [
                          TextField(
                            key: const ValueKey(
                              'admin-customer-username-field',
                            ),
                            controller: username,
                            enabled: isNew,
                            textDirection: TextDirection.ltr,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'اسم المستخدم',
                              helperText: isNew
                                  ? 'اختياري. إن تُرك فارغاً تُستخدم أرقام الهاتف كاسم مستخدم. الدخول يقبل رقم الهاتف.'
                                  : 'لا يمكن تغيير اسم المستخدم بعد الإنشاء',
                              helperMaxLines: 3,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const ValueKey(
                              'admin-customer-password-field',
                            ),
                            controller: password,
                            obscureText: obscurePassword,
                            textDirection: TextDirection.ltr,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText:
                                  isNew ? 'كلمة المرور' : 'كلمة مرور جديدة',
                              helperText: isNew
                                  ? 'اختياري. إن تُركت فارغة يولّد الخادم كلمة مرور مؤقتة. لا تُوضع في الرابط.'
                                  : 'اتركه فارغاً للإبقاء على كلمة المرور الحالية. تُحفظ في الخادم فقط، وليس في الرابط.',
                              helperMaxLines: 3,
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
                          const SizedBox(height: 14),
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
                        ],
                      ),
                      const SizedBox(height: 14),
                      _CustomerFormSection(
                        key: const ValueKey(
                          'admin-customer-section-discount',
                        ),
                        title: 'الخصم والحالة',
                        icon: Icons.tune_outlined,
                        children: [
                          TextField(
                            key: const ValueKey(
                              'admin-customer-discount-field',
                            ),
                            controller: discount,
                            keyboardType:
                                const TextInputType.numberWithOptions(
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
                              helperMaxLines: 2,
                              suffixText: '%',
                              prefixIcon: Icon(Icons.percent),
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            key: const ValueKey(
                              'admin-customer-status-field',
                            ),
                            initialValue: statusValue,
                            decoration:
                                const InputDecoration(labelText: 'الحالة'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'active', child: Text('نشط')),
                              DropdownMenuItem(
                                  value: 'suspended', child: Text('موقوف')),
                              DropdownMenuItem(
                                  value: 'archived', child: Text('مؤرشف')),
                            ],
                            onChanged: (value) => setDialogState(
                              () => statusValue = value ?? 'active',
                            ),
                          ),
                        ],
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 12),
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
              ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء')),
                FilledButton(
                  key: const ValueKey('admin-customer-form-save'),
                  onPressed: () {
                    final parsedDiscount =
                        _parseCustomerDiscountPercent(discount.text);
                    final nextPassword = password.text.trim();
                    final nextUsername = isNew
                        ? resolveCustomerCreateUsername(
                            username: username.text,
                            phone: phone.text,
                          )
                        : customer.username.trim();
                    if (parsedDiscount == null) {
                      setDialogState(() {
                        validationMessage =
                            'نسبة الخصم يجب أن تكون بين 0 و99.99 وبحد أقصى منزلتين عشريتين.';
                      });
                      return;
                    }
                    if (contact.text.trim().isEmpty ||
                        business.text.trim().isEmpty ||
                        phone.text.trim().isEmpty ||
                        city.text.trim().isEmpty) {
                      setDialogState(() {
                        validationMessage =
                            'أدخل الشخص المسؤول واسم المتجر والهاتف والمدينة.';
                      });
                      return;
                    }
                    if (nextUsername.isEmpty) {
                      setDialogState(() {
                        validationMessage = isNew
                            ? 'أدخل اسم مستخدم، أو اتركه فارغاً لاستخدام أرقام الهاتف.'
                            : 'أدخل اسم المستخدم.';
                      });
                      return;
                    }
                    if (isNew && !isValidCustomerUsername(nextUsername)) {
                      setDialogState(() {
                        validationMessage =
                            'اسم المستخدم 3-64 حرفاً لاتينياً أو رقماً، ويمكن استخدام . _ -';
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
                          username: nextUsername,
                          contactPerson: contact.text.trim(),
                          phone: phone.text.trim(),
                          phoneIsWhatsapp: true,
                          city: city.text.trim(),
                          area: area.text.trim(),
                          address: customer.address,
                          creditLimit: customer.creditLimit,
                          outstandingBalance: customer.outstandingBalance,
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
            );
          },
        ),
      ),
    );
    if (saved == null) return;
    InviteResult? invite;
    BusinessCustomer? inviteCustomer;
    await _runCustomerAction(saved.customer.id, () async {
      final repo = ref.read(adminRepositoryProvider);
      final template = await ref
          .read(customerInviteTemplateStoreProvider)
          .load();
      if (saved.customer.id == 'new') {
        final result = await repo.createCustomerInvite(
          saved.customer,
          password: saved.password.isEmpty ? null : saved.password,
          inviteTemplate: template,
        );
        _rememberPassword(
          customerId: result.customerId,
          username: result.username,
          password: result.temporaryPassword,
        );
        invite = result;
        inviteCustomer = saved.customer.copyWith(
          id: result.customerId.isNotEmpty
              ? result.customerId
              : saved.customer.id,
          profileId: result.profileId,
          username: result.username,
        );
      } else {
        await repo.saveCustomer(saved.customer);
        if (saved.password.isNotEmpty) {
          await repo.setCustomerPassword(
            saved.customer,
            password: saved.password,
          );
          _rememberPassword(
            customerId: saved.customer.id,
            username: saved.customer.username,
            password: saved.password,
          );
          invite = repo.composeLoginReminder(
            saved.customer,
            knownPassword: saved.password,
            inviteTemplate: template,
          );
          inviteCustomer = saved.customer;
        }
      }
      if (mounted) {
        await reloadAfterMutation(
          this,
          () => _refreshCustomers(keepResults: true),
        );
      }
    });
    if (mounted && invite != null) {
      await _showInviteResult(invite!, customer: inviteCustomer);
    }
  }

  String? _knownPasswordFor(BusinessCustomer customer) {
    return _sessionKnownPasswords[customer.id] ??
        _sessionKnownPasswords['user:${customer.username}'];
  }

  void _rememberPassword({
    required String username,
    required String password,
    String? customerId,
  }) {
    final trimmed = password.trim();
    if (trimmed.isEmpty) return;
    if (customerId != null &&
        customerId.isNotEmpty &&
        customerId != 'new') {
      _sessionKnownPasswords[customerId] = trimmed;
    }
    if (username.trim().isNotEmpty) {
      _sessionKnownPasswords['user:${username.trim()}'] = trimmed;
    }
  }

  Future<void> _showInviteTemplateSettings() async {
    final store = ref.read(customerInviteTemplateStoreProvider);
    final current = await store.load();
    if (!mounted) return;
    final next = await showDialog<String>(
      context: context,
      builder: (context) => _InviteTemplateDialog(initialTemplate: current),
    );
    if (next == null || !mounted) return;
    final ok = await store.save(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'تم حفظ نص الدعوة على هذا الجهاز.'
              : 'تعذر حفظ النص. حاولوا مرة أخرى.',
        ),
      ),
    );
  }

  Future<void> _showInviteResult(
    InviteResult result, {
    BusinessCustomer? customer,
  }) async {
    final shopName = (await ref.read(adminRepositoryProvider).settings()).shopName;
    final template =
        await ref.read(customerInviteTemplateStoreProvider).load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => WhatsAppInviteDialog(
        result: result,
        customer: customer,
        shopName: shopName,
        template: template,
        onRotatePassword: customer == null ||
                customer.id.isEmpty ||
                customer.id == 'new'
            ? null
            : (password) async {
                await ref.read(adminRepositoryProvider).setCustomerPassword(
                      customer,
                      password: password,
                    );
                _rememberPassword(
                  customerId: customer.id,
                  username: customer.username,
                  password: password,
                );
              },
      ),
    );
  }
}

class _InviteTemplateDialog extends StatefulWidget {
  const _InviteTemplateDialog({required this.initialTemplate});

  final String initialTemplate;

  @override
  State<_InviteTemplateDialog> createState() => _InviteTemplateDialogState();
}

class _InviteTemplateDialogState extends State<_InviteTemplateDialog> {
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
        title: const Text('نص دعوة واتساب الافتراضي'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'يُستخدم هذا النص لكل الدعوات الجديدة ورسائل الترحيب. '
                  'يمكن تعديل رسالة واحدة من أيقونة القلم قبل النسخ.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'العناصر النائبة: ${customerInviteTemplatePlaceholders.join('  ')}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('admin-invite-template-field'),
                  controller: _controller,
                  minLines: 10,
                  maxLines: 18,
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    labelText: 'نص القالب',
                    helperText:
                        'رابط الدخول يبقى /login فقط. لا تضعوا كلمة المرور داخل الرابط.',
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
              _controller.text = defaultCustomerInviteTemplate;
            }),
            child: const Text('استعادة الافتراضي'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('حفظ للدعوات الجديدة'),
          ),
        ],
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

class _CustomerFormSection extends StatelessWidget {
  const _CustomerFormSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.darkGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

String? _adminCustomerPasswordError(String password, String confirmation) {
  if (password != confirmation.trim()) {
    return 'كلمتا المرور غير متطابقتين.';
  }
  if (password.isEmpty) {
    return 'أدخل كلمة المرور أو اترك الحقلين فارغين.';
  }
  if (password.length > 128) {
    return 'يجب ألا تتجاوز كلمة المرور 128 حرفاً.';
  }
  return null;
}

String _customerActionErrorAr(Object error) {
  final info = AdminRepository.describeRemoteError(error);
  final code = info.code.toUpperCase();
  final detail = info.message.trim();
  final mapped = switch (code) {
    'CUSTOMER_UPDATE_INVALID' => 'بيانات العميل غير صالحة.',
    'CUSTOMER_UPDATE_FAILED' => 'تعذر حفظ حالة العميل في الخادم.',
    'CUSTOMER_UPDATE_CONFLICT' ||
    'STALE_WRITE' =>
      'تم تحديث هذا العنصر من جهاز آخر. أعد التحميل.',
    'CUSTOMER_NOT_FOUND' => 'لم يتم العثور على حساب العميل.',
    'CUSTOMER_TARGET_REQUIRED' => 'يمكن تحديث حسابات العملاء فقط.',
    'STAFF_AUTH_REQUIRED' ||
    'ADMIN_AUTH_REQUIRED' ||
    'FORBIDDEN' =>
      'ليست لديكم صلاحية لتعديل هذا العميل.',
    'VALIDATION_ERROR' => detail.toLowerCase().contains('account_status')
        ? 'حالة الحساب يجب أن تكون نشط أو موقوف أو مؤرشف.'
        : detail.toLowerCase().contains('phone')
            ? 'رقم الهاتف غير صالح. استخدموا رقماً محلياً أو دولياً واضحاً.'
            : 'بيانات العميل غير مكتملة أو غير صالحة.',
    'PASSWORD_TOO_SHORT' => 'كلمة المرور غير مقبولة. استخدموا 1 إلى 128 حرفاً.',
    _ => '',
  };
  if (mapped.isNotEmpty) {
    if (detail.isNotEmpty &&
        !_isGenericEnglishServerMessage(detail) &&
        !mapped.contains(detail)) {
      return '$mapped $detail';
    }
    if (code.isNotEmpty && code != mapped) {
      return '$mapped ($code)';
    }
    return mapped;
  }
  if (detail.isNotEmpty && !_looksLikeRawException(detail)) {
    return 'تعذر إكمال العملية: $detail';
  }
  if (code.isNotEmpty) {
    return 'تعذر إكمال العملية ($code).';
  }
  if (error.toString().toLowerCase().contains('password')) {
    return 'كلمة المرور غير مقبولة. استخدموا 1 إلى 128 حرفاً.';
  }
  return 'تعذر إكمال العملية. تحقق من الاتصال وحاول مجدداً.';
}

bool _isGenericEnglishServerMessage(String message) {
  const generic = {
    'the request could not be completed.',
    'the customer account could not be updated.',
    'the customer whatsapp preference could not be saved.',
  };
  return generic.contains(message.toLowerCase());
}

bool _looksLikeRawException(String message) {
  final lower = message.toLowerCase();
  return lower.startsWith('functionexception') ||
      lower.startsWith('stateerror') ||
      lower.startsWith('instance of');
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
