import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/order_status.dart';
import '../models/admin_models.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../remote/supabase_clients.dart';

final adminRepositoryProvider =
    Provider<AdminRepository>((ref) => AdminRepository());

class InviteResult {
  const InviteResult({
    required this.username,
    required this.temporaryPassword,
    required this.inviteLink,
    required this.whatsappMessage,
    required this.customerPhone,
  });

  final String username;
  final String temporaryPassword;
  final String inviteLink;
  final String whatsappMessage;
  final String customerPhone;
}

class AdminRepository {
  final List<BusinessCustomer> _customers = [
    const BusinessCustomer(
      id: 'customer-1',
      profileId: 'customer-user-1',
      businessName: 'شركة طرابلس للحيوانات الأليفة',
      username: 'tripoli-pets',
      contactPerson: 'محمد السنوسي',
      phone: '+218910000001',
      city: 'طرابلس',
      area: 'حي الأندلس',
      address: 'شارع تجاري قريب من الطريق الرئيسي',
      priceGroup: 'جملة',
      creditLimit: 2500,
      outstandingBalance: 420,
    ),
    const BusinessCustomer(
      id: 'customer-2',
      businessName: 'شركة بنغازي للتوريدات',
      username: 'benghazi-supplies',
      contactPerson: 'أحمد البرعصي',
      phone: '+218920000002',
      city: 'بنغازي',
      area: 'الهواري',
      priceGroup: 'جملة',
    ),
    const BusinessCustomer(
      id: 'customer-3',
      businessName: 'مزرعة الواحة',
      username: 'alwaha-farm',
      contactPerson: 'سالم علي',
      phone: '+218930000003',
      city: 'مصراتة',
      area: 'الدافنية',
      priceGroup: 'خاص',
      accountStatus: 'suspended',
    ),
  ];

  AppSettingsData _settings = const AppSettingsData(
    shopName: AppConfig.shopName,
    supportWhatsapp: AppConfig.supportWhatsapp,
    downloadLink: AppConfig.downloadLink,
    apkLink: AppConfig.apkLink,
  );

  final List<AppBanner> _banners = const [
    AppBanner(
      id: 'banner-1',
      title: 'عروض خاصة لتجار مستلزمات الحيوانات',
      body: 'اطلب الأعلاف والمستلزمات بالجملة بسهولة',
      ctaText: 'تسوق الآن',
      imageUrl:
          'https://images.unsplash.com/photo-1714068691210-073dc52c6c1d?auto=format&fit=crop&w=1600&h=620&q=80',
      targetType: 'category',
      targetValue: 'كلاب',
      sortOrder: 1,
    ),
  ];

  final List<AdminNotification> _notifications = const [
    AdminNotification(
      id: 'notif-1',
      title: 'طلب جديد',
      body: 'شركة طرابلس للحيوانات الأليفة أرسل طلباً جديداً',
      type: 'new_order',
      orderId: 'o1001',
    ),
  ];

  Future<AdminDashboardStats> dashboardStats(
      List<Product> products, List<Order> orders) async {
    final customers = await listCustomers();
    final now = DateTime.now();
    return AdminDashboardStats(
      totalCustomers: customers.length,
      activeCustomers: customers.where((customer) => customer.active).length,
      pendingOrders:
          orders.where((order) => order.status == OrderStatus.pending).length,
      todayOrders: orders
          .where((order) =>
              order.createdAt.year == now.year &&
              order.createdAt.month == now.month &&
              order.createdAt.day == now.day)
          .length,
      lowStockCount: products.where((product) => product.lowStock).length,
      monthSales: orders
          .where((order) =>
              order.createdAt.year == now.year &&
              order.createdAt.month == now.month &&
              order.status == OrderStatus.delivered)
          .fold(0, (sum, order) => sum + order.total),
    );
  }

  Future<List<BusinessCustomer>> listCustomers(
      {String query = '', String? status}) async {
    final client = supabaseClient;
    if (client != null) {
      final rows = await client
          .from('business_customers')
          .select('*, profiles(username), price_groups(name)')
          .order('created_at', ascending: false);
      return rows
          .map<BusinessCustomer>((row) => BusinessCustomer.fromSupabase(row))
          .where((customer) {
        final q = query.trim();
        return (status == null || customer.accountStatus == status) &&
            (q.isEmpty ||
                customer.businessName.contains(q) ||
                customer.username.contains(q) ||
                customer.phone.contains(q) ||
                customer.city.contains(q));
      }).toList();
    }
    final q = query.trim();
    return _customers.where((customer) {
      return (status == null || customer.accountStatus == status) &&
          (q.isEmpty ||
              customer.businessName.contains(q) ||
              customer.username.contains(q) ||
              customer.phone.contains(q) ||
              customer.city.contains(q));
    }).toList();
  }

  Future<BusinessCustomer> saveCustomer(BusinessCustomer customer) async {
    final client = supabaseClient;
    if (client != null) {
      final saved = await client
          .from('business_customers')
          .update({
            'business_name': customer.businessName,
            'contact_person': customer.contactPerson,
            'phone': customer.phone,
            'city': customer.city,
            'area': customer.area,
            'address': customer.address,
            'account_status': customer.accountStatus,
            'credit_limit': customer.creditLimit,
            'outstanding_balance': customer.outstandingBalance,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', customer.id)
          .select('*, profiles(username), price_groups(name)')
          .single();
      return BusinessCustomer.fromSupabase(saved);
    }
    final index = _customers.indexWhere((item) => item.id == customer.id);
    if (index == -1) {
      _customers.insert(0, customer);
    } else {
      _customers[index] = customer;
    }
    return customer;
  }

  Future<InviteResult> createCustomerInvite(BusinessCustomer customer) async {
    final client = supabaseClient;
    if (client != null) {
      final response =
          await client.functions.invoke('admin-create-customer', body: {
        'business_name': customer.businessName,
        'contact_person': customer.contactPerson,
        'phone': customer.phone,
        'city': customer.city,
        'area': customer.area,
        'address': customer.address,
        'username': customer.username,
        'download_link': _settings.downloadLink,
        'shop_name': _settings.shopName,
      });
      final data = response.data as Map<String, dynamic>;
      return InviteResult(
        username: data['username'].toString(),
        temporaryPassword: data['temporaryPassword'].toString(),
        inviteLink: data['inviteLink'].toString(),
        whatsappMessage: data['whatsappMessage'].toString(),
        customerPhone: customer.phone,
      );
    }
    final id = customer.id == 'new' ? const Uuid().v4() : customer.id;
    final saved = customer.copyWith(id: id, accountStatus: 'active');
    await saveCustomer(saved);
    const temporaryPassword = 'Temp-92841!';
    final token = 'inv_${const Uuid().v4().substring(0, 8)}';
    final inviteLink =
        'animalsupplyb2b://invite?token=$token&client=${Uri.encodeComponent(saved.username)}';
    final message = _inviteMessage(
        saved.businessName, saved.username, temporaryPassword, inviteLink);
    return InviteResult(
        username: saved.username,
        temporaryPassword: temporaryPassword,
        inviteLink: inviteLink,
        whatsappMessage: message,
        customerPhone: saved.phone);
  }

  Future<InviteResult> resetCustomerPassword(BusinessCustomer customer) async {
    final client = supabaseClient;
    if (client != null && customer.profileId != null) {
      final response = await client.functions.invoke(
          'admin-reset-customer-password',
          body: {'user_id': customer.profileId});
      final data = response.data as Map<String, dynamic>;
      const token = 'reset-token-not-used-in-password';
      final inviteLink =
          'animalsupplyb2b://invite?token=$token&client=${Uri.encodeComponent(customer.username)}';
      final temp = data['temporaryPassword'].toString();
      return InviteResult(
          username: customer.username,
          temporaryPassword: temp,
          inviteLink: inviteLink,
          whatsappMessage: _inviteMessage(
              customer.businessName, customer.username, temp, inviteLink),
          customerPhone: customer.phone);
    }
    const temp = 'Temp-48291!';
    final inviteLink =
        'animalsupplyb2b://invite?token=reset_demo&client=${Uri.encodeComponent(customer.username)}';
    return InviteResult(
        username: customer.username,
        temporaryPassword: temp,
        inviteLink: inviteLink,
        whatsappMessage: _inviteMessage(
            customer.businessName, customer.username, temp, inviteLink),
        customerPhone: customer.phone);
  }

  Future<AppSettingsData> settings() async {
    final client = supabaseClient;
    if (client != null) {
      final rows = await client.from('app_settings').select('key,value');
      return AppSettingsData.fromKeyValues({
        for (final row in rows) row['key'].toString(): row['value'].toString()
      });
    }
    return _settings;
  }

  Future<void> saveSettings(AppSettingsData settings) async {
    final client = supabaseClient;
    _settings = settings;
    if (client != null) {
      await client.from('app_settings').upsert([
        for (final entry in settings.toKeyValues().entries)
          {
            'key': entry.key,
            'value': entry.value,
            'updated_at': DateTime.now().toIso8601String()
          }
      ]);
    }
  }

  Future<List<AppBanner>> banners() async {
    final client = supabaseClient;
    if (client != null) {
      final rows = await client
          .from('banners')
          .select()
          .eq('active', true)
          .order('sort_order');
      return rows.map<AppBanner>((row) => AppBanner.fromSupabase(row)).toList();
    }
    return _banners;
  }

  Future<AppVersionInfo> latestVersion() async {
    final client = supabaseClient;
    if (client != null) {
      final row = await client
          .from('app_versions')
          .select()
          .eq('platform', 'android')
          .eq('published', true)
          .order('version_code', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) {
        return AppVersionInfo(
          platform: (row['platform'] ?? 'android').toString(),
          versionName: (row['version_name'] ?? '1.0.0').toString(),
          versionCode: (row['version_code'] ?? 1) as int,
          apkUrl: (row['apk_url'] ?? '').toString(),
          required: row['required_update'] == true,
          releaseNotes: (row['release_notes'] ?? '').toString(),
        );
      }
    }
    return AppVersionInfo(
        apkUrl: _settings.apkLink,
        releaseNotes: 'رابط APK تجريبي للاختبار المباشر.');
  }

  Future<List<AdminNotification>> notifications() async {
    final client = supabaseClient;
    if (client != null) {
      final rows = await client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(30);
      return rows
          .map<AdminNotification>((row) => AdminNotification(
                id: row['id'].toString(),
                title: (row['title'] ?? '').toString(),
                body: (row['body'] ?? '').toString(),
                type: (row['type'] ?? '').toString(),
                orderId:
                    (row['payload'] is Map ? row['payload']['order_id'] : null)
                        ?.toString(),
                read: row['read_at'] != null,
              ))
          .toList();
    }
    return _notifications;
  }

  String _inviteMessage(String businessName, String username,
      String temporaryPassword, String inviteLink) {
    return '''مرحباً $businessName 👋

تم إنشاء حسابكم في تطبيق ${_settings.shopName} لطلبات الأعلاف ومستلزمات الحيوانات بالجملة.

بيانات الدخول:
اسم المستخدم: $username
كلمة المرور المؤقتة: $temporaryPassword

رابط تحميل التطبيق:
${_settings.downloadLink}

رابط تفعيل الحساب:
$inviteLink

ملاحظة: حفاظاً على أمان حسابكم، يرجى تغيير كلمة المرور بعد أول تسجيل دخول.''';
  }
}
