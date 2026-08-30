import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/support/customer_invite_copy.dart';
import '../../core/support/invite_delivery.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';

enum _PasswordApplyChoice { cancel, messageOnly, rotateOnServer }

class WhatsAppInviteDialog extends StatefulWidget {
  const WhatsAppInviteDialog({
    super.key,
    required this.result,
    required this.shopName,
    required this.template,
    this.customer,
    this.onRotatePassword,
  });

  final InviteResult result;
  final BusinessCustomer? customer;
  final String shopName;
  final String template;
  final Future<void> Function(String password)? onRotatePassword;

  @override
  State<WhatsAppInviteDialog> createState() => _WhatsAppInviteDialogState();
}

class _WhatsAppInviteDialogState extends State<WhatsAppInviteDialog> {
  late final TextEditingController _greeting;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _loginUrl;
  late String _originalPassword;
  var _editing = false;
  var _busy = false;

  bool get _isDemo => AppConfig.isDemoMode;

  @override
  void initState() {
    super.initState();
    _greeting = TextEditingController(
      text: widget.result.businessName.isNotEmpty
          ? widget.result.businessName
          : (widget.customer?.businessName ?? ''),
    );
    _username = TextEditingController(text: widget.result.username);
    _originalPassword = widget.result.temporaryPassword;
    _password = TextEditingController(text: _originalPassword);
    final fromMessage = sanitizeInviteLoginUrl(
      _loginUrlFromMessage(widget.result.whatsappMessage),
    );
    _loginUrl = TextEditingController(
      text: fromMessage.isNotEmpty
          ? fromMessage
          : sanitizeInviteLoginUrl(widget.result.inviteLink),
    );
    _greeting.addListener(_rebuildPreview);
    _username.addListener(_rebuildPreview);
    _password.addListener(_rebuildPreview);
    _loginUrl.addListener(_rebuildPreview);
  }

  @override
  void dispose() {
    _greeting.dispose();
    _username.dispose();
    _password.dispose();
    _loginUrl.dispose();
    super.dispose();
  }

  String _loginUrlFromMessage(String message) {
    final match =
        RegExp(r'https?://[^\s]+', caseSensitive: false).firstMatch(message);
    return match?.group(0) ?? '';
  }

  String get _preview {
    return renderCustomerInviteTemplate(
      template: widget.template,
      businessName: _greeting.text,
      shopName: widget.shopName,
      username: _username.text,
      loginUrl: sanitizeInviteLoginUrl(_loginUrl.text),
      password: _password.text,
      contactName: widget.result.contactName.isNotEmpty
          ? widget.result.contactName
          : widget.customer?.contactPerson,
    );
  }

  void _rebuildPreview() {
    if (mounted) setState(() {});
  }

  bool get _canRotate {
    final id = widget.customer?.id ?? widget.result.customerId;
    return !_isDemo &&
        widget.onRotatePassword != null &&
        id.isNotEmpty &&
        id != 'new';
  }

  Future<String?> _messageForSend() async {
    final nextPassword = _password.text.trim();
    final passwordChanged = nextPassword != _originalPassword.trim();
    if (nextPassword.isNotEmpty && passwordChanged && _canRotate) {
      final choice = await showDialog<_PasswordApplyChoice>(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تعيين كلمة المرور في الحساب؟'),
            content: const Text(
              'غيّرتم كلمة المرور في هذه الرسالة. هل تريدون حفظها في حساب العميل '
              'على الخادم حتى يستطيع الدخول بها؟ إن اخترتم «للرسالة فقط» تظهر في واتساب '
              'دون تغيير كلمة المرور الحالية في النظام.',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _PasswordApplyChoice.cancel),
                child: const Text('إلغاء'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, _PasswordApplyChoice.messageOnly),
                child: const Text('للرسالة فقط'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _PasswordApplyChoice.rotateOnServer),
                child: const Text('نعم، تعيين في الخادم'),
              ),
            ],
          ),
        ),
      );
      if (choice == null || choice == _PasswordApplyChoice.cancel) {
        return null;
      }
      if (choice == _PasswordApplyChoice.rotateOnServer) {
        setState(() => _busy = true);
        try {
          await widget.onRotatePassword!(nextPassword);
          _originalPassword = nextPassword;
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'تعذر تعيين كلمة المرور في الخادم. لم تُجهّز الرسالة.',
                ),
              ),
            );
          }
          return null;
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }
    }
    return _preview;
  }

  Future<void> _copyMessage({bool closeAfter = true}) async {
    final message = await _messageForSend();
    if (message == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: message));
    if (closeAfter && mounted) Navigator.pop(context);
  }

  Future<void> _openWhatsapp(String? phone) async {
    final message = await _messageForSend();
    if (message == null || !mounted) return;
    final url = inviteWhatsappComposeUri(
      normalizedPhone: phone,
      text: message,
    );
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'تم فتح واتساب والنص جاهز للإرسال.'
              : 'تعذر فتح واتساب. يمكنكم نسخ الرسالة يدوياً.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDemo = _isDemo;
    final normalizedPhone =
        _normalizeLibyanWhatsapp(widget.result.customerPhone);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                isDemo ? 'حساب تجريبي محلي' : 'رسالة واتساب آمنة',
              ),
            ),
            IconButton(
              key: const Key('admin-invite-edit-pen'),
              tooltip: 'تعديل',
              onPressed:
                  _busy ? null : () => setState(() => _editing = !_editing),
              icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
            ),
          ],
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
                      'رقم واتساب العميل غير صحيح. يمكن فتح واتساب بالنص جاهزاً دون رقم، أو نسخ الرسالة، أو تصحيح الرقم من بيانات العميل.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      Icon(
                        Icons.phone_android,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'سيتم فتح واتساب على الرقم $normalizedPhone '
                          'والنص جاهز في خانة الكتابة.',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ]),
                  ),
                if (_editing) ...[
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('admin-invite-field-greeting'),
                    controller: _greeting,
                    decoration: const InputDecoration(
                      labelText: 'اسم التحية',
                      helperText: 'يظهر بعد مرحباً',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('admin-invite-field-username'),
                    controller: _username,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('admin-invite-field-password'),
                    controller: _password,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      helperText:
                          'تُكتب في الرسالة فقط. لا تُوضع في رابط الدخول. إن غيّرتموها يمكن حفظها في الخادم عند الإرسال.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('admin-invite-field-login-url'),
                    controller: _loginUrl,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'رابط تسجيل الدخول',
                      helperText: 'يُحفظ كمسار /login فقط، بلا كلمة مرور.',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SelectableText(
                  _preview,
                  key: const Key('admin-invite-preview'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          if (!isDemo) ...[
            OutlinedButton.icon(
              key: const Key('admin-invite-open-whatsapp'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xff25d366),
              ),
              onPressed: _busy ? null : () => _openWhatsapp(normalizedPhone),
              icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 18),
              label: Text(
                normalizedPhone == null ? 'إرسال عبر واتساب' : 'فتح واتساب',
              ),
            ),
            FilledButton.icon(
              key: const Key('admin-invite-copy'),
              onPressed: _busy ? null : () => _copyMessage(),
              icon: const Icon(Icons.copy),
              label: const Text('نسخ'),
            ),
          ] else
            FilledButton.icon(
              onPressed: _busy ? null : () => _copyMessage(),
              icon: const Icon(Icons.copy),
              label: const Text('نسخ النص التجريبي'),
            ),
        ],
      ),
    );
  }
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
