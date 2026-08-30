import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/push_notifications.dart';
import 'auth_controller.dart';
import 'widgets/auth_pattern_background.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final newPassword = TextEditingController();
  final confirmation = TextEditingController();
  bool showPassword = false;

  @override
  void dispose() {
    newPassword.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('تغيير كلمة المرور'),
          actions: [
            TextButton.icon(
              onPressed: auth.loading
                  ? null
                  : () => ref
                      .read(pushNotificationsCoordinatorProvider)
                      .signOut(controller),
              icon: const Icon(Icons.logout),
              label: const Text('خروج'),
            ),
          ],
        ),
        body: AuthPatternBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 36,
                          spreadRadius: 0,
                          offset: const Offset(0, 14),
                        ),
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.07),
                          blurRadius: 18,
                          spreadRadius: -2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Card(
                          elevation: 0,
                          color: Colors.white.withValues(alpha: 0.94),
                          surfaceTintColor: Colors.transparent,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 28,
                            ),
                            child: AutofillGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Icon(
                                    Icons.password_outlined,
                                    size: 54,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'أنشئ كلمة مرور خاصة بك',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'لأمان الحساب، يجب تغيير كلمة المرور المؤقتة قبل '
                                    'استخدام التطبيق. يجب أن يكون رابط الدعوة الحالي '
                                    'قد فُتح وتم التحقق منه.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  TextField(
                                    controller: newPassword,
                                    enabled: !auth.loading,
                                    obscureText: !showPassword,
                                    enableSuggestions: false,
                                    autocorrect: false,
                                    autofillHints: const [
                                      AutofillHints.newPassword
                                    ],
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      labelText: 'كلمة المرور الجديدة',
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      suffixIcon: IconButton(
                                        tooltip: showPassword
                                            ? 'إخفاء كلمة المرور'
                                            : 'إظهار كلمة المرور',
                                        onPressed: () => setState(
                                          () => showPassword = !showPassword,
                                        ),
                                        icon: Icon(
                                          showPassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: confirmation,
                                    enabled: !auth.loading,
                                    obscureText: !showPassword,
                                    enableSuggestions: false,
                                    autocorrect: false,
                                    autofillHints: const [
                                      AutofillHints.newPassword
                                    ],
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: auth.loading
                                        ? null
                                        : (_) =>
                                            controller.changeRequiredPassword(
                                              newPassword.text,
                                              confirmation.text,
                                            ),
                                    decoration: const InputDecoration(
                                      labelText: 'تأكيد كلمة المرور',
                                      prefixIcon:
                                          Icon(Icons.lock_reset_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    '10 أحرف على الأقل، وتتضمن حرفاً إنجليزياً كبيراً '
                                    'وصغيراً ورقماً ورمزاً.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  if (auth.error != null) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error
                                            .withValues(alpha: 0.08),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        auth.error!,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  FilledButton.icon(
                                    onPressed: auth.loading
                                        ? null
                                        : () =>
                                            controller.changeRequiredPassword(
                                              newPassword.text,
                                              confirmation.text,
                                            ),
                                    icon: auth.loading
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.check_circle_outline),
                                    label: Text(
                                      auth.loading
                                          ? 'جار الحفظ...'
                                          : 'حفظ ومتابعة',
                                    ),
                                  ),
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
            ),
          ),
        ),
      ),
    );
  }
}
