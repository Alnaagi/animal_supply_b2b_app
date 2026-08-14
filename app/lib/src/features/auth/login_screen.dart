import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  final inviteCode = TextEditingController();

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    inviteCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final authController = ref.read(authControllerProvider.notifier);
    final theme = Theme.of(context);
    const fieldRadius = BorderRadius.all(Radius.circular(16));
    final loginTheme = theme.copyWith(
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: const Color(0xfff5f9f7),
        focusColor: AppTheme.green.withValues(alpha: 0.08),
        hoverColor: AppTheme.green.withValues(alpha: 0.04),
        contentPadding:
            const EdgeInsetsDirectional.fromSTEB(18, 18, 14, 18),
        labelStyle: const TextStyle(
          color: Color(0xff48645b),
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: const TextStyle(
          color: AppTheme.green,
          fontWeight: FontWeight.w800,
        ),
        helperStyle: const TextStyle(
          color: Color(0xff5d716a),
          height: 1.4,
        ),
        helperMaxLines: 2,
        hintStyle: const TextStyle(color: Color(0xff789087)),
        prefixIconColor: AppTheme.green,
        prefixIconConstraints: const BoxConstraints(
          minWidth: 56,
          minHeight: 56,
        ),
        border: const OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(
            color: Color(0xffbdd2ca),
            width: 1.25,
          ),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(
            color: Color(0xffbdd2ca),
            width: 1.25,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(
            color: AppTheme.green,
            width: 2,
          ),
        ),
        disabledBorder: const OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(
            color: Color(0xffd8e2de),
          ),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(
            color: AppTheme.red,
            width: 1.25,
          ),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(
            color: AppTheme.red,
            width: 2,
          ),
        ),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Theme(
                    key: const Key('login-input-theme'),
                    data: loginTheme,
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xffe3f3eb)),
                        child: const Icon(Icons.pets,
                            size: 42, color: AppTheme.green),
                      ),
                      const SizedBox(height: 14),
                      Text(AppConfig.shopName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      const Text(
                          'مرحباً بك في منصة طلبات الجملة للأعلاف ومستلزمات الحيوانات',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      TextField(
                        key: const Key('login-invite-field'),
                        controller: inviteCode,
                        enabled: !auth.loading,
                        decoration: const InputDecoration(
                          labelText: 'رمز الدعوة',
                          hintText: 'أدخل الرمز المرسل من المتجر',
                          helperText:
                              'لأول دخول أو إعادة التعيين فقط. الحسابات المفعلة '
                              'لا تحتاجه، ولا تضع كلمة المرور هنا.',
                          prefixIcon: Icon(Icons.link),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const Key('login-username-field'),
                        controller: username,
                        enabled: !auth.loading,
                        decoration: const InputDecoration(
                          labelText: 'اسم المستخدم أو الهاتف أو البريد',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const Key('login-password-field'),
                        controller: password,
                        enabled: !auth.loading,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      if (auth.error != null) ...[
                        const SizedBox(height: 12),
                        Text(auth.error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: auth.loading
                              ? null
                              : () => authController.login(
                                  username.text, password.text),
                          child: Text(auth.loading ? 'جار التحقق...' : 'دخول')),
                      const SizedBox(height: 12),
                      const Text(
                          'لا تملك حساب؟ تواصل مع المتجر لإنشاء حساب خاص بك',
                          textAlign: TextAlign.center),
                      const Divider(height: 28),
                      Text('تجربة سريعة',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _DemoLoginButton(
                                label: 'مدير',
                                icon: Icons.admin_panel_settings_outlined,
                                onPressed: auth.loading
                                    ? null
                                    : () => authController.login(
                                        'admin@demo.ly', 'Admin123!')),
                            _DemoLoginButton(
                                label: 'موظف',
                                icon: Icons.badge_outlined,
                                onPressed: auth.loading
                                    ? null
                                    : () => authController.login(
                                        'staff@demo.ly', 'Staff123!')),
                            _DemoLoginButton(
                                label: 'عميل',
                                icon: Icons.storefront_outlined,
                                onPressed: auth.loading
                                    ? null
                                    : () => authController.login(
                                        'tripoli-pets', 'Customer123!')),
                          ]),
                    ],
                  ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoLoginButton extends StatelessWidget {
  const _DemoLoginButton(
      {required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
}
