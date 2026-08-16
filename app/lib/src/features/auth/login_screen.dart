import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/shop_branding.dart';
import '../../core/localization/arabic_copy.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/branded_auth_loading.dart';
import '../../core/widgets/shop_brand_logo.dart';
import '../../data/repositories/demo_data.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.inviteToken,
    this.clientCode,
  });

  final String? inviteToken;
  final String? clientCode;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final TextEditingController username;
  late final TextEditingController password;

  bool get hasInviteFromLink => widget.inviteToken?.trim().isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    username = TextEditingController(text: widget.clientCode?.trim() ?? '');
    password = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCode = oldWidget.clientCode?.trim() ?? '';
    final newCode = widget.clientCode?.trim() ?? '';
    if (newCode != oldCode &&
        (username.text.trim().isEmpty || username.text.trim() == oldCode)) {
      username.text = newCode;
    }
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthController controller) {
    return controller.login(
      username.text,
      password.text,
      inviteToken: widget.inviteToken,
      clientCode: widget.clientCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final authController = ref.read(authControllerProvider.notifier);
    final branding = ref.watch(shopBrandingProvider);
    final configurationBlocked = AppConfig.configurationBlocked;
    final theme = Theme.of(context);
    const fieldRadius = BorderRadius.all(Radius.circular(16));
    final loginTheme = theme.copyWith(
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: const Color(0xfff5f9f7),
        focusColor: AppTheme.green.withValues(alpha: 0.08),
        hoverColor: AppTheme.green.withValues(alpha: 0.04),
        contentPadding: const EdgeInsetsDirectional.fromSTEB(18, 18, 14, 18),
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
      body: Stack(
        children: [
          SafeArea(
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
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: ShopBrandLogo(
                              logoUrl: branding.logoUrl,
                              size: 74,
                              backgroundColor: const Color(0xffe3f3eb),
                              fallbackIconColor: AppTheme.green,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            branding.shopName,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'مرحباً بك في منصة طلبات الجملة لدى ${branding.shopName}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          _EnvironmentBanner(
                            message: auth.notice ??
                                (configurationBlocked
                                    ? AppConfig.configurationMessageAr
                                    : null),
                            isError: configurationBlocked,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('login-username-field'),
                            controller: username,
                            enabled: !auth.loading,
                            autofillHints: const [AutofillHints.username],
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'اسم المستخدم أو رقم الهاتف',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('login-password-field'),
                            controller: password,
                            enabled: !auth.loading,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: auth.loading || configurationBlocked
                                ? null
                                : (_) => _submit(authController),
                            decoration: const InputDecoration(
                              labelText: 'كلمة المرور',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                          ),
                          if (hasInviteFromLink) ...[
                            const SizedBox(height: 14),
                            const _InviteReceivedCard(),
                          ],
                          if (auth.error != null) ...[
                            const SizedBox(height: 12),
                            _AuthMessage(
                              message: auth.error!,
                              isError: true,
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: auth.loading || configurationBlocked
                                ? null
                                : () => _submit(authController),
                            child: Text(
                              auth.loading ? 'جار التحقق...' : 'دخول',
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'ليس لديك حساب؟ تواصل مع المتجر لإنشاء حساب أعمال خاص بك.',
                            textAlign: TextAlign.center,
                          ),
                          if (AppConfig.allowsDemoCredentials) ...[
                            const Divider(height: 28),
                            Text(
                              'تجربة سريعة — بيانات غير حقيقية',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
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
                                            'admin',
                                            demoAdminPassword,
                                          ),
                                ),
                                _DemoLoginButton(
                                  label: 'موظف',
                                  icon: Icons.badge_outlined,
                                  onPressed: auth.loading
                                      ? null
                                      : () => authController.login(
                                            'staff',
                                            demoStaffPassword,
                                          ),
                                ),
                                _DemoLoginButton(
                                  label: 'عميل',
                                  icon: Icons.storefront_outlined,
                                  onPressed: auth.loading
                                      ? null
                                      : () => authController.login(
                                            'tripoli-pets',
                                            demoCustomerPassword,
                                          ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
          if (auth.loading || auth.bootstrapping)
            BrandedAuthLoading(
              asOverlay: true,
              message: auth.bootstrapping && !auth.loading
                  ? ArabicCopy.sessionRestore
                  : ArabicCopy.loginVerifying,
            ),
        ],
      ),
    );
  }
}

class _InviteReceivedCard extends StatelessWidget {
  const _InviteReceivedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xffeaf4ff),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffb8d8f4)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: Color(0xff1769aa)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'تم استلام رابط الدعوة الآمن. أدخل بيانات الدخول المؤقتة '
              'التي أرسلها المتجر لإكمال التفعيل.',
            ),
          ),
        ],
      ),
    );
  }
}

class _EnvironmentBanner extends StatelessWidget {
  const _EnvironmentBanner({
    required this.message,
    required this.isError,
  });

  final String? message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    return _AuthMessage(message: message!, isError: isError);
  }
}

class _AuthMessage extends StatelessWidget {
  const _AuthMessage({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color =
        isError ? Theme.of(context).colorScheme.error : const Color(0xff8a5a00);
    final background =
        isError ? color.withValues(alpha: 0.08) : const Color(0xfffff4d6);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DemoLoginButton extends StatelessWidget {
  const _DemoLoginButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}
