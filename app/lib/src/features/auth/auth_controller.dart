import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_user.dart';
import '../../data/remote/supabase_clients.dart';
import '../../data/repositories/demo_data.dart';

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});

class AuthState {
  const AuthState({this.user, this.loading = false, this.error});
  final AppUser? user;
  final bool loading;
  final String? error;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState());

  Future<void> login(String username, String password) async {
    state = const AuthState(loading: true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final normalized = username.trim().toLowerCase();
    if (supabaseClient != null &&
        !normalized.endsWith('@demo.ly') &&
        normalized != 'admin' &&
        normalized != 'staff' &&
        normalized != 'tripoli-pets') {
      try {
        final email = normalized.contains('@')
            ? normalized
            : '$normalized@example.invalid';
        final result = await supabaseClient!.auth
            .signInWithPassword(email: email, password: password);
        final user = result.user;
        if (user == null) {
          state = const AuthState(error: 'تعذر تسجيل الدخول من Supabase.');
          return;
        }
        final profile = await supabaseClient!
            .from('profiles')
            .select('id, username, role')
            .eq('id', user.id)
            .single();
        final customer = profile['role'] == 'customer'
            ? await supabaseClient!
                .from('business_customers')
                .select('id, business_name')
                .eq('profile_id', user.id)
                .maybeSingle()
            : null;
        state = AuthState(
          user: AppUser(
            id: user.id,
            username: (profile['username'] ?? email).toString(),
            role: (profile['role'] ?? 'customer').toString(),
            businessName: customer == null
                ? null
                : (customer['business_name'] ?? '').toString(),
            customerId: customer == null ? null : customer['id'].toString(),
          ),
        );
        return;
      } catch (_) {
        state = const AuthState(
            error:
                'فشل تسجيل الدخول من Supabase. تحقق من البيانات أو استخدم حسابات demo.');
        return;
      }
    }
    if ((normalized == 'admin@demo.ly' || normalized == 'admin') &&
        password == 'Admin123!') {
      state = const AuthState(user: demoAdmin);
    } else if ((normalized == 'staff@demo.ly' || normalized == 'staff') &&
        password == 'Staff123!') {
      state = const AuthState(user: demoStaff);
    } else if ((normalized == 'tripoli-pets' ||
            normalized == 'customer@demo.ly') &&
        password == 'Customer123!') {
      state = const AuthState(user: demoCustomer);
    } else {
      state = const AuthState(
          error:
              'بيانات الدخول غير صحيحة. للتجربة استخدم الحسابات الموجودة في README.');
    }
  }

  Future<void> logout() async {
    if (supabaseClient != null) {
      await supabaseClient!.auth.signOut();
    }
    state = const AuthState();
  }
}
