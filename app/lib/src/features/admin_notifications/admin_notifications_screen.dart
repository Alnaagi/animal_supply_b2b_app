import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/admin_models.dart';
import '../../data/models/notification_campaign_summary.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/notifications_repository.dart';
import '../admin_dashboard/admin_shell.dart';

class AdminNotificationsScreen extends ConsumerStatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  ConsumerState<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState
    extends ConsumerState<AdminNotificationsScreen> {
  final title = TextEditingController();
  final body = TextEditingController();
  final customerSearch = TextEditingController();
  final Set<String> selectedProfiles = {};
  String audience = 'all_customers';
  String? selectedProductId;
  bool sending = false;
  String? _pendingCampaignId;
  String? _pendingCampaignFingerprint;
  late Future<List<NotificationCampaignSummary>> _campaignHistory;
  late Future<List<Object>> _formData;

  @override
  void initState() {
    super.initState();
    _campaignHistory =
        ref.read(notificationsRepositoryProvider).listCampaignSummaries();
    _formData = Future.wait<Object>([
      ref.read(adminRepositoryProvider).listCustomers(status: 'active'),
      ref.read(catalogRepositoryProvider).products(),
    ]);
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    customerSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'إرسال الإشعارات',
      child: FutureBuilder<List<Object>>(
        future: _formData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => setState(() {
                  _formData = Future.wait<Object>([
                    ref
                        .read(adminRepositoryProvider)
                        .listCustomers(status: 'active'),
                    ref.read(catalogRepositoryProvider).products(),
                  ]);
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('تعذر تحميل بيانات الحملة — إعادة المحاولة'),
              ),
            );
          }
          final customers = (snapshot.data?[0] ?? <BusinessCustomer>[])
              as List<BusinessCustomer>;
          final products = (snapshot.data?[1] ?? <Product>[]) as List<Product>;
          final visibleCustomers = customers
              .where(
                  (customer) => _matchesCustomer(customerSearch.text, customer))
              .toList(growable: false);
          final selectableVisibleProfiles = visibleCustomers
              .map((customer) => customer.profileId)
              .whereType<String>()
              .toSet();
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'حملة إشعار جديدة',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'سيتم حفظ الإشعار داخل التطبيق وإرساله للأجهزة '
                          'المسجلة عند تفعيل Firebase.',
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: audience,
                          decoration:
                              const InputDecoration(labelText: 'الجمهور'),
                          items: const [
                            DropdownMenuItem(
                              value: 'all_customers',
                              child: Text('كل العملاء النشطين'),
                            ),
                            DropdownMenuItem(
                              value: 'selected_profiles',
                              child: Text('عملاء محددون'),
                            ),
                            DropdownMenuItem(
                              value: 'all_staff',
                              child: Text('كل الموظفين والمديرين'),
                            ),
                          ],
                          onChanged: sending
                              ? null
                              : (value) => setState(
                                    () => audience = value ?? 'all_customers',
                                  ),
                        ),
                        if (audience == 'selected_profiles') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: customerSearch,
                            enabled: !sending,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              labelText: 'بحث باسم النشاط أو المدينة أو الهاتف',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'تم اختيار ${selectedProfiles.length} عميل',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    sending || selectableVisibleProfiles.isEmpty
                                        ? null
                                        : () => setState(
                                              () => selectedProfiles.addAll(
                                                  selectableVisibleProfiles),
                                            ),
                                icon: const Icon(Icons.select_all),
                                label: const Text('تحديد النتائج الظاهرة'),
                              ),
                              TextButton(
                                onPressed: sending || selectedProfiles.isEmpty
                                    ? null
                                    : () => setState(
                                          selectedProfiles.clear,
                                        ),
                                child: const Text('مسح التحديد'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 300),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                if (visibleCustomers.isEmpty)
                                  const ListTile(
                                    leading: Icon(Icons.search_off),
                                    title: Text(
                                      'لا يوجد عميل مطابق لهذا البحث',
                                    ),
                                  ),
                                for (final customer in visibleCustomers)
                                  CheckboxListTile(
                                    value: customer.profileId != null &&
                                        selectedProfiles
                                            .contains(customer.profileId),
                                    onChanged: customer.profileId == null ||
                                            sending
                                        ? null
                                        : (checked) => setState(() {
                                              if (checked == true) {
                                                selectedProfiles
                                                    .add(customer.profileId!);
                                              } else {
                                                selectedProfiles
                                                    .remove(customer.profileId);
                                              }
                                            }),
                                    title: Text(customer.businessName),
                                    subtitle: Text(
                                        '${customer.city} • ${customer.phone}'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: title,
                          enabled: !sending,
                          maxLength: 120,
                          decoration:
                              const InputDecoration(labelText: 'عنوان الإشعار'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: body,
                          enabled: !sending,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 600,
                          decoration:
                              const InputDecoration(labelText: 'نص الإشعار'),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          key: ValueKey(selectedProductId),
                          initialValue: selectedProductId,
                          decoration: const InputDecoration(
                            labelText: 'فتح منتج عند الضغط (اختياري)',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('بدون رابط منتج'),
                            ),
                            for (final product in products)
                              DropdownMenuItem(
                                value: product.id,
                                child: Text('${product.name} • ${product.sku}'),
                              ),
                          ],
                          onChanged: sending
                              ? null
                              : (value) =>
                                  setState(() => selectedProductId = value),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: sending ? null : _confirmAndSend,
                          icon: sending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(
                              sending ? 'جار الإرسال...' : 'مراجعة وإرسال'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _CampaignHistoryCard(
                  history: _campaignHistory,
                  onRefresh: _refreshCampaignHistory,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _matchesCustomer(String rawQuery, BusinessCustomer customer) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      customer.businessName,
      customer.username,
      customer.city,
      customer.area,
      customer.phone,
      customer.contactPerson,
    ].any((value) => value.toLowerCase().contains(query));
  }

  Future<void> _confirmAndSend() async {
    final cleanTitle = title.text.trim();
    final cleanBody = body.text.trim();
    if (cleanTitle.isEmpty ||
        cleanBody.isEmpty ||
        (audience == 'selected_profiles' && selectedProfiles.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أكمل العنوان والنص وحدد الجمهور أولاً.')),
      );
      return;
    }

    final cleanProductId = selectedProductId ?? '';
    final fingerprint = _campaignFingerprint(
      title: cleanTitle,
      body: cleanBody,
      productId: cleanProductId,
    );
    if (_pendingCampaignFingerprint != fingerprint) {
      _pendingCampaignFingerprint = fingerprint;
      _pendingCampaignId = NotificationsRepository.newCampaignIdempotencyKey();
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد إرسال الإشعار'),
        content: Text(
          audience == 'selected_profiles'
              ? 'سيتم إرسال الإشعار إلى ${selectedProfiles.length} عميل محدد.'
              : audience == 'all_staff'
                  ? 'سيتم إرسال الإشعار إلى كل الموظفين والمديرين النشطين.'
                  : 'سيتم إرسال الإشعار إلى كل العملاء النشطين.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => sending = true);
    try {
      final count =
          await ref.read(notificationsRepositoryProvider).sendCampaign(
                title: cleanTitle,
                body: cleanBody,
                audienceType: audience,
                profileIds: selectedProfiles.toList(),
                productId: cleanProductId,
                idempotencyKey: _pendingCampaignId!,
              );
      if (!mounted) return;
      title.clear();
      body.clear();
      selectedProductId = null;
      selectedProfiles.clear();
      _pendingCampaignId = null;
      _pendingCampaignFingerprint = null;
      _campaignHistory =
          ref.read(notificationsRepositoryProvider).listCampaignSummaries();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء الإشعار لـ $count مستلم.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر إرسال الإشعار. تحقق من الاتصال والصلاحيات.'),
        ),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  String _campaignFingerprint({
    required String title,
    required String body,
    required String productId,
  }) {
    final profiles = selectedProfiles.toList()..sort();
    return jsonEncode({
      'title': title,
      'body': body,
      'product_id': productId,
      'audience': audience,
      'profile_ids': profiles,
    });
  }

  void _refreshCampaignHistory() {
    setState(() {
      _campaignHistory =
          ref.read(notificationsRepositoryProvider).listCampaignSummaries();
    });
  }
}

class _CampaignHistoryCard extends StatelessWidget {
  const _CampaignHistoryCard({
    required this.history,
    required this.onRefresh,
  });

  final Future<List<NotificationCampaignSummary>> history;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'سجل حملات الإشعارات',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  tooltip: 'تحديث السجل',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'يعرض حالة صف الإرسال وعدد الرسائل التي قبلها مزود الإشعارات للأجهزة.',
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<NotificationCampaignSummary>>(
              future: history,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return const Text(
                    'تعذر تحميل سجل الحملات. تحقق من الاتصال وتطبيق آخر ترحيل لقاعدة البيانات.',
                  );
                }
                final campaigns =
                    snapshot.data ?? const <NotificationCampaignSummary>[];
                if (campaigns.isEmpty) {
                  return const Text('لا توجد حملات مرسلة حتى الآن.');
                }
                return Column(
                  children: [
                    for (var index = 0; index < campaigns.length; index++) ...[
                      _CampaignHistoryRow(campaign: campaigns[index]),
                      if (index != campaigns.length - 1)
                        const Divider(height: 24),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignHistoryRow extends StatelessWidget {
  const _CampaignHistoryRow({required this.campaign});

  final NotificationCampaignSummary campaign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          campaign.title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          '${_audienceLabel(campaign.audience)} • ${_dateLabel(campaign.createdAt)}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SummaryChip(
              label: 'المستلمون ${campaign.recipientCount}',
              color: theme.colorScheme.primaryContainer,
            ),
            _SummaryChip(
              label: 'اكتمل ${campaign.completedCount}',
              color: Colors.green.shade100,
            ),
            if (campaign.pendingCount > 0)
              _SummaryChip(
                label: 'قيد الانتظار ${campaign.pendingCount}',
                color: Colors.amber.shade100,
              ),
            if (campaign.retryingCount > 0)
              _SummaryChip(
                label: 'إعادة محاولة ${campaign.retryingCount}',
                color: Colors.orange.shade100,
              ),
            if (campaign.deadCount > 0)
              _SummaryChip(
                label: 'يحتاج مراجعة ${campaign.deadCount}',
                color: Colors.red.shade100,
              ),
            _SummaryChip(
              label: 'قبلها مزود الإشعارات ${campaign.deviceSentCount}',
              color: Colors.blue.shade100,
            ),
          ],
        ),
      ],
    );
  }

  static String _audienceLabel(Map<String, dynamic> audience) {
    return switch (audience['type']?.toString()) {
      'role' when audience['role'] == 'customer' => 'كل العملاء',
      'roles' => 'الموظفون والمديرون',
      'profile_ids' => 'عملاء محددون',
      'city' => 'عملاء مدينة محددة',
      _ => 'جمهور الحملة',
    };
  }

  static String _dateLabel(DateTime value) {
    final date = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${date.year}/${twoDigits(date.month)}/${twoDigits(date.day)} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
