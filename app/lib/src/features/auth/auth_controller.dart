import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../core/config/app_config.dart';
import '../../core/config/app_runtime_mode.dart';
import '../../core/auth/login_identifier.dart';
import '../../core/auth/account_bootstrap.dart';
import '../../data/local/local_auth_session_store.dart';
import '../../data/models/app_user.dart';
import '../../data/remote/supabase_clients.dart';
import '../../data/repositories/demo_data.dart';

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final controller = AuthController();
  unawaited(controller.restoreSession());
  return controller;
});

class AuthState {
  const AuthState({
    this.user,
    this.loading = false,
    this.bootstrapping = false,
    this.error,
    this.notice,
    this.restoredRoute,
  });

  final AppUser? user;
  final bool loading;
  final bool bootstrapping;
  final String? error;
  final String? notice;
  final String? restoredRoute;

  bool get isAuthenticated => user != null;
  bool get requiresPasswordChange => user?.mustChangePassword ?? false;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController({LocalAuthSessionStore? sessionStore})
      : _sessionStore = sessionStore ?? LocalAuthSessionStore.instance,
        super(const AuthState(loading: true, bootstrapping: true));

  final LocalAuthSessionStore _sessionStore;
  StreamSubscription<supabase.AuthState>? _authSubscription;
  bool _interactiveAuthInProgress = false;
  bool _disposed = false;
  bool _restoreStarted = false;
  int _accountLoadRevision = 0;
  String? _restoredRoute;

  Future<void> restoreSession() async {
    if (_restoreStarted || _disposed) return;
    _restoreStarted = true;
    _restoredRoute = await _sessionStore.readLastRoute();
    if (_disposed) return;

    if (AppConfig.remoteBackendEnabled) {
      await _bootstrapRemoteSession();
      return;
    }
    await _bootstrapLocalSession();
  }

  Future<void> _bootstrapLocalSession() async {
    final message = AppConfig.configurationMessageAr;
    if (!AppConfig.allowsDemoCredentials) {
      await _sessionStore.clearDemoUser();
      if (_disposed) return;
      state = AuthState(
        error: AppConfig.configurationBlocked ? message : null,
        notice: AppConfig.configurationBlocked ? null : message,
      );
      return;
    }

    final user = await _sessionStore.readDemoUser();
    if (_disposed) return;
    if (user == null) {
      state = AuthState(
        error: AppConfig.configurationBlocked ? message : null,
        notice: AppConfig.configurationBlocked ? null : message,
      );
      return;
    }
    state = AuthState(
      user: user,
      notice: 'حساب تجريبي: أي تغييرات هنا ليست بيانات تشغيل حقيقية.',
      restoredRoute: _restoredRoute,
    );
  }

  Future<void> _bootstrapRemoteSession() async {
    await _sessionStore.clearDemoUser();
    final client = supabaseClient;
    if (client == null) {
      if (!_disposed) {
        state = AuthState(error: AppConfig.configurationMessageAr);
      }
      return;
    }

    _authSubscription = client.auth.onAuthStateChange.listen(
      (event) {
        if (_disposed) return;
        if (event.event == supabase.AuthChangeEvent.signedOut) {
          if (_interactiveAuthInProgress) return;
          if (client.auth.currentUser != null) return;
          unawaited(_sessionStore.clear());
          state = AuthState(
            notice:
                AppConfig.isDemoMode ? AppConfig.configurationMessageAr : null,
          );
          return;
        }
        if (_interactiveAuthInProgress) return;
        final authUser = event.session?.user ?? client.auth.currentUser;
        if (event.event == supabase.AuthChangeEvent.initialSession) {
          if (authUser != null) {
            unawaited(_loadAndPublishAccount(authUser, bootstrapping: true));
          } else if (state.bootstrapping && state.user == null) {
            state = const AuthState();
          }
          return;
        }
        if (authUser != null &&
            (event.event == supabase.AuthChangeEvent.signedIn ||
                event.event == supabase.AuthChangeEvent.userUpdated ||
                event.event == supabase.AuthChangeEvent.passwordRecovery ||
                event.event == supabase.AuthChangeEvent.tokenRefreshed)) {
          unawaited(_loadAndPublishAccount(authUser, bootstrapping: false));
        }
      },
      onError: (_) {
        if (!_disposed && state.user == null) {
          state = const AuthState(
            error: 'تعذر متابعة جلسة الدخول. تحقق من الاتصال ثم أعد المحاولة.',
          );
        }
      },
    );

    final authUser = client.auth.currentUser ?? client.auth.currentSession?.user;
    if (authUser == null) {
      if (!_disposed) state = const AuthState();
      return;
    }
    await _loadAndPublishAccount(authUser, bootstrapping: true);
  }

  Future<void> retrySessionCheck() async {
    final client = supabaseClient;
    final authUser = client?.auth.currentUser;
    if (client == null || authUser == null) {
      state = AuthState(
        error: AppConfig.isProduction
            ? AppConfig.configurationMessageAr ??
                'لا يمكن التحقق من الجلسة في نسخة الإنتاج.'
            : null,
        notice:
            AppConfig.isProduction ? null : AppConfig.configurationMessageAr,
      );
      return;
    }
    await _loadAndPublishAccount(authUser, bootstrapping: true);
  }

  Future<void> login(
    String username,
    String password, {
    String? inviteToken,
    String? clientCode,
  }) async {
    if (state.loading || state.bootstrapping) return;

    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty || password.isEmpty) {
      state = AuthState(
        error: 'أدخل اسم المستخدم أو رقم الهاتف وكلمة المرور.',
        notice: state.notice,
      );
      return;
    }

    final cleanInviteToken = inviteToken?.trim() ?? '';
    final cleanClientCode = clientCode?.trim() ?? '';
    if (cleanInviteToken.isNotEmpty && !_isValidInviteToken(cleanInviteToken)) {
      state = AuthState(
        error: 'رمز الدعوة غير صالح. افتح الرابط المرسل من المتجر من جديد.',
        notice: state.notice,
      );
      return;
    }
    if (cleanClientCode.length > 120) {
      state = AuthState(
        error: 'كود العميل غير صالح.',
        notice: state.notice,
      );
      return;
    }

    if (AppConfig.allowsDemoCredentials &&
        matchesDemoLoginCredentials(normalized, password)) {
      final overlayReady = await _activateLocalDemoOverlayIfNeeded();
      if (overlayReady || !AppConfig.remoteBackendEnabled) {
        await _loginDemo(normalized, password);
        return;
      }
    }

    if (!AppConfig.remoteBackendEnabled) {
      if (!AppConfig.allowsDemoCredentials) {
        state = AuthState(
          error: AppConfig.configurationMessageAr ??
              'نسخة الإنتاج غير متصلة بالخادم، ولا يسمح فيها بحسابات التجربة.',
        );
        return;
      }
      await _loginDemo(normalized, password);
      return;
    }

    final client = supabaseClient;
    if (client == null) {
      state = const AuthState(
        error: 'تعذر الوصول إلى خدمة الدخول. أعد تشغيل التطبيق وحاول مجدداً.',
      );
      return;
    }

    _interactiveAuthInProgress = true;
    state = const AuthState(loading: true);
    try {
      final target = await _resolveRemoteLoginTarget(client, normalized) ??
          loginAuthTargetForIdentifier(
            identifier: normalized,
            customerLoginDomain: AppConfig.customerLoginDomain,
          );
      if (target == null) {
        state = AuthState(
          error: normalizeLibyanLoginPhone(normalized) == null &&
                  !normalized.contains('@') &&
                  !isValidCustomerLoginDomain(AppConfig.customerLoginDomain)
              ? 'دخول العملاء غير مهيأ بعد. راجع نطاق حسابات العملاء.'
              : 'أدخل اسم مستخدم صالحاً أو رقم هاتف.',
        );
        return;
      }
      final result = await client.auth.signInWithPassword(
        email: target.email,
        phone: target.phone,
        password: password,
      );
      final authUser = result.user;
      if (authUser == null) {
        state = const AuthState(
          error: 'تعذر تسجيل الدخول. تحقق من البيانات وحاول مجدداً.',
        );
        return;
      }

      if (cleanInviteToken.isNotEmpty) {
        try {
          await _redeemInvite(
            token: cleanInviteToken,
            clientCode: cleanClientCode.isEmpty ? null : cleanClientCode,
          );
        } catch (_) {
          await _signOutSilently();
          state = const AuthState(
            error:
                'تعذر تفعيل الدعوة. قد يكون الرابط منتهياً أو مستخدماً من قبل.',
          );
          return;
        }
      }

      await _loadAndPublishAccount(authUser, bootstrapping: false);
    } on supabase.AuthException {
      state = const AuthState(
        error: 'بيانات الدخول غير صحيحة أو أن الحساب غير متاح حالياً.',
      );
    } catch (_) {
      state = const AuthState(
        error: 'تعذر إكمال تسجيل الدخول. تحقق من الاتصال ثم أعد المحاولة.',
      );
    } finally {
      _interactiveAuthInProgress = false;
    }
  }

  Future<bool> _activateLocalDemoOverlayIfNeeded() async {
    if (AppConfig.isProduction) return false;
    if (!AppConfig.hasInitializedRemoteBackend) return true;
    if (!AppRuntimeMode.preferLocalDemo) {
      final result = await AppRuntimeMode.setPreferLocalDemo(
        true,
        productionBackendAvailable: true,
      );
      if (!result.applied || !AppRuntimeMode.preferLocalDemo) {
        return false;
      }
    }
    await _authSubscription?.cancel();
    _authSubscription = null;
    return true;
  }

  Future<void> _loginDemo(String normalized, String password) async {
    state = AuthState(
      loading: true,
      notice: AppConfig.configurationMessageAr,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_disposed) return;

    AppUser? user;
    final demoPhone = normalizeLibyanLoginPhone(normalized);
    final customerPhone = normalizeLibyanLoginPhone(demoCustomer.phone ?? '');
    if ((normalized == 'admin' || normalized == 'admin@demo.ly') &&
        password == demoAdminPassword) {
      user = demoAdmin.copyWith(isDemo: true);
    } else if ((normalized == 'staff' || normalized == 'staff@demo.ly') &&
        password == demoStaffPassword) {
      user = demoStaff.copyWith(isDemo: true);
    } else if ((normalized == 'tripoli-pets' ||
            normalized == 'customer@demo.ly' ||
            (demoPhone != null && demoPhone == customerPhone)) &&
        password == demoCustomerPassword) {
      user = demoCustomer.copyWith(
        accountStatus: 'active',
        isDemo: true,
      );
    }

    if (user == null) {
      state = AuthState(
        error: 'بيانات الدخول غير صحيحة لحسابات التجربة.',
        notice: AppConfig.configurationMessageAr,
      );
      return;
    }
    await _sessionStore.saveDemoUser(user);
    if (_disposed) return;
    state = AuthState(
      user: user,
      notice: 'حساب تجريبي: أي تغييرات هنا ليست بيانات تشغيل حقيقية.',
      restoredRoute: _restoredRoute,
    );
  }

  Future<LoginAuthTarget?> _resolveRemoteLoginTarget(
    supabase.SupabaseClient client,
    String identifier,
  ) async {
    try {
      final payload = await client.rpc(
        'resolve_login_identifier',
        params: {'p_identifier': identifier},
      );
      if (payload is! Map) return null;
      final data = <String, dynamic>{
        for (final entry in payload.entries) entry.key.toString(): entry.value,
      };
      final email = data['email']?.toString().trim() ?? '';
      final phone = data['phone']?.toString().trim() ?? '';
      final typedPhone = normalizeLibyanLoginPhone(identifier);
      if (typedPhone != null) {
        if (phone.isNotEmpty) return LoginAuthTarget.phone(phone);
        return LoginAuthTarget.phone(typedPhone);
      }
      if (email.isNotEmpty) {
        return LoginAuthTarget.email(email.toLowerCase());
      }
      if (phone.isNotEmpty) return LoginAuthTarget.phone(phone);
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _redeemInvite({
    required String token,
    String? clientCode,
  }) async {
    final client = supabaseClient;
    if (client == null || client.auth.currentUser == null) {
      throw const _AuthFlowException();
    }

    final response = await client.functions.invoke(
      AppConfig.redeemInviteFunction,
      body: <String, dynamic>{
        'token': token,
        if (clientCode != null && clientCode.isNotEmpty)
          'client_code': clientCode,
      },
    );
    final data = response.data;
    final accepted =
        data is Map && (data['success'] == true || data['redeemed'] == true);
    if (!accepted) throw const _AuthFlowException();
  }

  Future<void> _loadAndPublishAccount(
    supabase.User authUser, {
    required bool bootstrapping,
  }) async {
    final revision = ++_accountLoadRevision;
    if (!_disposed) {
      state = AuthState(
        loading: true,
        bootstrapping: bootstrapping,
        user: state.user?.id == authUser.id ? state.user : null,
        restoredRoute: _restoredRoute,
      );
    }

    try {
      final appUser = await _fetchRemoteAccount(authUser);
      if (_disposed || revision != _accountLoadRevision) return;
      state = AuthState(user: appUser, restoredRoute: _restoredRoute);
    } on _AccountRejected catch (error) {
      if (_disposed || revision != _accountLoadRevision) return;
      await _signOutSilently();
      if (!_disposed) state = AuthState(error: error.message);
    } catch (_) {
      if (_disposed || revision != _accountLoadRevision) return;
      state = const AuthState(
        error: 'تعذر التحقق من صلاحية الحساب. تحقق من الاتصال ثم أعد المحاولة.',
      );
    }
  }

  Future<AppUser> _fetchRemoteAccount(supabase.User authUser) async {
    final client = supabaseClient;
    if (client == null) throw const _AuthFlowException();

    try {
      final payload = await client.rpc('bootstrap_current_account');
      return appUserFromBootstrapPayload(
        payload,
        authUserId: authUser.id,
        fallbackIdentifier: authUser.email ?? authUser.phone,
      );
    } on AccountBootstrapException catch (error) {
      throw _AccountRejected(error.message);
    }
  }

  Future<void> changeRequiredPassword(
    String newPassword,
    String confirmation,
  ) async {
    final currentUser = state.user;
    if (currentUser == null || !currentUser.mustChangePassword) return;
    if (state.loading) return;

    final validationError = _validateNewPassword(newPassword, confirmation);
    if (validationError != null) {
      state = AuthState(user: currentUser, error: validationError);
      return;
    }

    final client = supabaseClient;
    final authUser = client?.auth.currentUser;
    if (client == null || authUser == null || authUser.id != currentUser.id) {
      state = AuthState(
        user: currentUser,
        error: 'انتهت جلسة الدخول. سجل الدخول من جديد لتغيير كلمة المرور.',
      );
      return;
    }

    _interactiveAuthInProgress = true;
    state = AuthState(user: currentUser, loading: true);
    try {
      final response = await client.functions.invoke(
        AppConfig.completePasswordChangeFunction,
        body: <String, dynamic>{'new_password': newPassword},
      );
      final data = response.data;
      final completed =
          data is Map && (data['success'] == true || data['completed'] == true);
      if (!completed) throw const _AuthFlowException();

      await _loadAndPublishAccount(authUser, bootstrapping: false);
    } catch (error) {
      final code = _functionErrorCode(error);
      state = AuthState(
        user: currentUser,
        error: code == 'INVITE_REDEMPTION_REQUIRED'
            ? 'يجب فتح رابط الدعوة أو إعادة تعيين كلمة المرور الحالي أولاً. '
                'إذا انتهت صلاحيته، اطلب رابطاً جديداً من الإدارة.'
            : 'تعذر إكمال تغيير كلمة المرور بأمان. '
                'حاول مرة أخرى بنفس كلمة المرور الجديدة، '
                'وإذا انتهت الجلسة فسجّل الدخول بها.',
      );
    } finally {
      _interactiveAuthInProgress = false;
    }
  }

  String? _validateNewPassword(String password, String confirmation) {
    if (password != confirmation) {
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

  bool _isValidInviteToken(String token) {
    return token.length >= 20 &&
        token.length <= 512 &&
        RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(token);
  }

  String? _functionErrorCode(Object error) {
    if (error is! supabase.FunctionException) return null;
    Object? value = error.details;
    if (value is Map) {
      final root = <String, dynamic>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
      final nested = root['error'];
      if (nested is Map) {
        final nestedMap = <String, dynamic>{
          for (final entry in nested.entries) entry.key.toString(): entry.value,
        };
        return nestedMap['code']?.toString();
      }
      return root['code']?.toString();
    }
    return null;
  }

  Future<void> _signOutSilently() async {
    final client = supabaseClient;
    if (client == null) return;
    try {
      await client.auth.signOut();
    } catch (_) {}
  }

  Future<void> logout() async {
    ++_accountLoadRevision;
    _restoredRoute = null;
    final client = supabaseClient;
    if (client != null) {
      try {
        await client.auth.signOut();
      } catch (_) {
        if (!_disposed) {
          state = AuthState(
            user: state.user,
            error: 'تعذر تسجيل الخروج من الخادم. تحقق من الاتصال وحاول مجدداً.',
          );
        }
        return;
      }
    }
    await _sessionStore.clear();
    if (!_disposed) {
      state = AuthState(
        notice: AppConfig.isDemoMode ? AppConfig.configurationMessageAr : null,
      );
    }
  }

  /// Confirms the signed-in admin password without changing session state
  /// on success. Demo accounts use the labelled local credentials only.
  Future<String?> verifyCurrentPassword(String password) async {
    if (password.trim().isEmpty) {
      return 'أدخل كلمة مرور حساب الإدارة.';
    }
    final user = state.user;
    if (user == null) {
      return 'انتهت جلسة الدخول. سجل الدخول من جديد ثم أعد المحاولة.';
    }

    if (!AppConfig.remoteBackendEnabled) {
      if (!user.isDemo || !AppConfig.allowsDemoCredentials) {
        return 'تعذر التحقق من كلمة المرور في هذا الوضع.';
      }
      final expected = user.isAdmin
          ? demoAdminPassword
          : user.isStaff
              ? demoStaffPassword
              : demoCustomerPassword;
      if (password != expected) {
        return 'كلمة المرور غير صحيحة.';
      }
      return null;
    }

    final client = supabaseClient;
    final email = client?.auth.currentUser?.email?.trim() ?? '';
    if (client == null || email.isEmpty) {
      return 'تعذر التحقق من كلمة المرور من الخادم.';
    }
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      return null;
    } on supabase.AuthException {
      return 'كلمة المرور غير صحيحة.';
    } catch (_) {
      return 'تعذر التحقق من كلمة المرور. تحقق من الاتصال ثم أعد المحاولة.';
    }
  }

  Future<void> enterLocalDemoSession() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
    if (!AppConfig.allowsDemoCredentials) {
      await _sessionStore.clearDemoUser();
      if (!_disposed) {
        state = AuthState(
          error: AppConfig.configurationMessageAr ??
              'الوضع التجريبي غير متاح في هذه النسخة.',
        );
      }
      return;
    }
    final user = demoAdmin.copyWith(isDemo: true);
    await _sessionStore.saveDemoUser(user);
    if (!_disposed) {
      state = AuthState(
        user: user,
        notice: 'حساب تجريبي: أي تغييرات هنا ليست بيانات تشغيل حقيقية.',
      );
    }
  }

  Future<void> rebindAfterRuntimeModeChange() async {
    ++_accountLoadRevision;
    await _authSubscription?.cancel();
    _authSubscription = null;
    if (AppConfig.remoteBackendEnabled) {
      await _sessionStore.clearDemoUser();
      if (!_disposed) {
        state = const AuthState(loading: true, bootstrapping: true);
      }
      await _bootstrapRemoteSession();
      return;
    }
    if (AppConfig.allowsDemoCredentials) {
      await enterLocalDemoSession();
      return;
    }
    await _sessionStore.clear();
    if (!_disposed) {
      state = AuthState(error: AppConfig.configurationMessageAr);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}

class _AccountRejected implements Exception {
  const _AccountRejected(this.message);

  final String message;
}

class _AuthFlowException implements Exception {
  const _AuthFlowException();
}
