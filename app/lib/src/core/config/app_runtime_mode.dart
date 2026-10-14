import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Local runtime overlay on top of compile-time [APP_ENV].
///
/// An explicit demo build still cannot silently attach to production just
/// because credentials exist on the machine. A production/staging build that
/// already initialized Supabase may prefer a labelled local demo overlay.
/// Production deploys default to remote data; a leftover v1 overlay from a
/// previous demo review build is ignored.
class AppRuntimeMode {
  static const preferLocalDemoPrefsKey = 'app_runtime.prefer_local_demo.v2';

  static bool _preferLocalDemo = false;
  static bool _loaded = false;

  static bool get preferLocalDemo =>
      !AppConfig.isProduction &&
      !kReleaseMode &&
      !AppConfig.hasSupabase &&
      _preferLocalDemo;
  static bool get loaded => _loaded;

  static Future<void> load({SharedPreferences? prefs}) async {
    try {
      final store = prefs ?? await SharedPreferences.getInstance();
      _preferLocalDemo = store.getBool(preferLocalDemoPrefsKey) == true;
    } catch (_) {
      _preferLocalDemo = false;
    }
    _loaded = true;
  }

  static Future<AppRuntimeSwitchResult> setPreferLocalDemo(
    bool preferDemo, {
    required bool productionBackendAvailable,
    SharedPreferences? prefs,
  }) async {
    if ((AppConfig.isProduction || AppConfig.hasSupabase || kReleaseMode) &&
        preferDemo) {
      return const AppRuntimeSwitchResult(
        applied: false,
        preferLocalDemo: false,
        messageAr: 'الوضع التجريبي غير متاح عند تفعيل خادم الإنتاج.',
      );
    }

    if (!preferDemo && !productionBackendAvailable) {
      return const AppRuntimeSwitchResult(
        applied: false,
        preferLocalDemo: true,
        messageAr:
            'لا يمكن تفعيل الإنتاج من هذه النسخة. إما أنها مبنية كتجربة محلية، '
            'أو إعدادات Supabase غير مكتملة. أعد البناء بـ APP_ENV=production '
            'مع مفاتيح عامة صحيحة، ولا تستخدم اختصارات غير آمنة.',
      );
    }

    try {
      final store = prefs ?? await SharedPreferences.getInstance();
      final saved = preferDemo
          ? await store.setBool(preferLocalDemoPrefsKey, true)
          : await store.remove(preferLocalDemoPrefsKey);
      if (!saved && preferDemo) {
        return AppRuntimeSwitchResult(
          applied: false,
          preferLocalDemo: _preferLocalDemo,
          messageAr: 'تعذر حفظ اختيار الوضع على هذا الجهاز.',
        );
      }
    } catch (_) {
      return AppRuntimeSwitchResult(
        applied: false,
        preferLocalDemo: _preferLocalDemo,
        messageAr: 'تعذر حفظ اختيار الوضع على هذا الجهاز.',
      );
    }

    _preferLocalDemo = preferDemo;
    _loaded = true;
    return AppRuntimeSwitchResult(
      applied: true,
      preferLocalDemo: _preferLocalDemo,
    );
  }

  @visibleForTesting
  static void debugReset({bool preferLocalDemo = false}) {
    _preferLocalDemo = preferLocalDemo;
    _loaded = true;
  }
}

class AppRuntimeSwitchResult {
  const AppRuntimeSwitchResult({
    required this.applied,
    required this.preferLocalDemo,
    this.messageAr,
  });

  final bool applied;
  final bool preferLocalDemo;
  final String? messageAr;
}

final appRuntimeModeProvider =
    StateNotifierProvider<AppRuntimeModeController, bool>(
  (ref) => AppRuntimeModeController(),
);

class AppRuntimeModeController extends StateNotifier<bool> {
  AppRuntimeModeController() : super(AppRuntimeMode.preferLocalDemo);

  Future<AppRuntimeSwitchResult> setPreferLocalDemo(
    bool preferDemo, {
    required bool productionBackendAvailable,
    SharedPreferences? prefs,
  }) async {
    final result = await AppRuntimeMode.setPreferLocalDemo(
      preferDemo,
      productionBackendAvailable: productionBackendAvailable,
      prefs: prefs,
    );
    if (result.applied) {
      state = result.preferLocalDemo;
    }
    return result;
  }
}
