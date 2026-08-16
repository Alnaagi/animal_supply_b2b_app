import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/login_identifier.dart';
import 'app_config_validation.dart';
import 'app_runtime_mode.dart';

enum AppEnvironment {
  demo,
  staging,
  production,
  invalid;

  static AppEnvironment fromValue(String value) {
    return switch (value.trim().toLowerCase()) {
      'demo' => AppEnvironment.demo,
      'production' || 'prod' => AppEnvironment.production,
      'staging' || 'stage' => AppEnvironment.staging,
      _ => AppEnvironment.invalid,
    };
  }
}

class AppConfig {
  static const environmentName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'demo',
  );
  static const shopName = String.fromEnvironment(
    'SHOP_NAME',
    defaultValue: 'المتجر',
  );
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const downloadLink = String.fromEnvironment(
    'APP_DOWNLOAD_LINK',
  );
  static const apkLink = String.fromEnvironment(
    'APK_LINK',
  );
  static const supportWhatsapp = String.fromEnvironment(
    'SUPPORT_WHATSAPP',
  );
  static const customerLoginDomain = String.fromEnvironment(
    'CUSTOMER_LOGIN_DOMAIN',
  );
  static const publicAppOrigin = String.fromEnvironment('APP_PUBLIC_ORIGIN');
  static const redeemInviteFunction = String.fromEnvironment(
    'REDEEM_INVITE_FUNCTION',
    defaultValue: 'redeem-invite',
  );
  static const completePasswordChangeFunction = String.fromEnvironment(
    'COMPLETE_PASSWORD_CHANGE_FUNCTION',
    defaultValue: 'complete-password-change',
  );
  static const sendNotificationCampaignFunction = String.fromEnvironment(
    'SEND_NOTIFICATION_CAMPAIGN_FUNCTION',
    defaultValue: 'send-notification-campaign',
  );
  static const registerDeviceTokenFunction = String.fromEnvironment(
    'REGISTER_DEVICE_TOKEN_FUNCTION',
    defaultValue: 'register-device-token',
  );
  static const unregisterDeviceTokenFunction = String.fromEnvironment(
    'UNREGISTER_DEVICE_TOKEN_FUNCTION',
    defaultValue: 'unregister-device-token',
  );
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseProjectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseMessagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const firebaseStorageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const firebaseAuthDomain =
      String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const firebaseAndroidAppId =
      String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const firebaseIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const firebaseWebAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const firebaseIosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'ly.animalsupply.b2b',
  );
  static const firebaseWebVapidKey =
      String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

  static final AppEnvironment environment =
      AppEnvironment.fromValue(environmentName);

  static bool _supabaseInitialized = false;
  static String? _supabaseInitializationError;

  static bool get hasSupabaseCredentials =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  static bool get hasFirebaseBaseConfig =>
      firebaseApiKey.isNotEmpty &&
      firebaseProjectId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty;

  static SupabasePublicConfigValidation get supabaseConfiguration =>
      validateSupabasePublicConfig(
        url: supabaseUrl,
        publicKey: supabaseAnonKey,
        allowLocalUrl: !isProduction,
      );

  static bool get hasValidSupabaseCredentials => supabaseConfiguration.isValid;

  static String? get firebaseConfigurationIssueAr =>
      firebaseClientConfigurationIssueAr(
        platform: kIsWeb
            ? FirebaseClientPlatform.web
            : switch (defaultTargetPlatform) {
                TargetPlatform.android => FirebaseClientPlatform.android,
                TargetPlatform.iOS => FirebaseClientPlatform.ios,
                _ => FirebaseClientPlatform.web,
              },
        apiKey: firebaseApiKey,
        projectId: firebaseProjectId,
        messagingSenderId: firebaseMessagingSenderId,
        webAppId: firebaseWebAppId,
        androidAppId: firebaseAndroidAppId,
        iosAppId: firebaseIosAppId,
        webVapidKey: firebaseWebVapidKey,
      );

  static bool get hasFirebaseConfigurationForCurrentPlatform =>
      firebaseConfigurationIssueAr == null;

  static String get supportWhatsappDigits =>
      supportWhatsapp.replaceAll(RegExp(r'[^0-9]'), '');

  static bool get hasSupportWhatsapp =>
      supportWhatsappDigits.length >= 8 && supportWhatsappDigits.length <= 15;

  /// True only after the Flutter Supabase client has initialized successfully.
  ///
  /// Repositories use this value to decide whether remote access is safe.
  static bool get hasSupabase => _supabaseInitialized;

  static bool get isProduction => environment == AppEnvironment.production;
  static bool get isStaging => environment == AppEnvironment.staging;
  static bool get hasValidEnvironment => environment != AppEnvironment.invalid;

  /// True when this process already initialized the public Supabase client.
  static bool get hasInitializedRemoteBackend =>
      (isProduction || isStaging) && _supabaseInitialized;

  /// Demo remains available for an explicit demo build, a labelled local
  /// overlay on a production/staging build, and as a fallback for an
  /// unconfigured non-production build.
  static bool get isDemoMode =>
      AppRuntimeMode.preferLocalDemo ||
      environment == AppEnvironment.demo ||
      (environment == AppEnvironment.staging && !_supabaseInitialized);

  /// Staging review builds may still use labelled local demo logins
  /// (`admin` / `admin`) even when public Supabase is initialized.
  /// Production never accepts those pairs unless the labelled overlay is on.
  static bool get allowsDemoCredentials =>
      isDemoMode || environment == AppEnvironment.staging;
  static bool get remoteBackendEnabled =>
      hasInitializedRemoteBackend && !AppRuntimeMode.preferLocalDemo;
  static bool get hasValidCustomerLoginDomain =>
      isValidCustomerLoginDomain(customerLoginDomain);
  static String? get publicAppOriginIssueAr =>
      validatePublicAppOriginAr(publicAppOrigin);
  static String get publicAppHost =>
      Uri.tryParse(publicAppOrigin.trim())?.host.toLowerCase() ?? '';
  static bool get configurationBlocked =>
      !hasValidEnvironment ||
      (isProduction &&
          !AppRuntimeMode.preferLocalDemo &&
          (!hasInitializedRemoteBackend ||
              !hasValidCustomerLoginDomain ||
              publicAppOriginIssueAr != null));

  static String? get configurationMessageAr {
    if (environment == AppEnvironment.invalid) {
      return 'قيمة APP_ENV غير صالحة. استخدم demo أو staging أو production.';
    }
    if (isProduction && !hasValidSupabaseCredentials) {
      return supabaseConfiguration.messageAr;
    }
    if (_supabaseInitializationError != null) {
      return _supabaseInitializationError;
    }
    if (isProduction && !hasValidCustomerLoginDomain) {
      return 'نسخة الإنتاج تحتاج CUSTOMER_LOGIN_DOMAIN حقيقياً ومملوكاً للعميل، '
          'ويجب أن يطابق إعداد Edge Functions.';
    }
    if (isProduction && publicAppOriginIssueAr != null) {
      return publicAppOriginIssueAr;
    }
    if (AppRuntimeMode.preferLocalDemo) {
      return 'وضع تجريبي محلي: البيانات المعروضة تجريبية وغير تشغيلية. '
          'خادم الإنتاج لم يُمسح.';
    }
    if (environment == AppEnvironment.demo) {
      return 'وضع تجريبي: البيانات محلية وليست بيانات تشغيل حقيقية.';
    }
    if (!_supabaseInitialized) {
      return 'تعذر الاتصال بالخادم، لذلك تعمل هذه النسخة في الوضع التجريبي فقط.';
    }
    return null;
  }

  static Future<void> tryInitializeSupabase() async {
    _supabaseInitialized = false;
    _supabaseInitializationError = null;

    // An explicit demo build must never start using a remote production
    // backend just because credentials happen to be present on the machine.
    if (environment == AppEnvironment.demo ||
        environment == AppEnvironment.invalid) {
      return;
    }
    if (!hasSupabaseCredentials) return;
    if (!hasValidSupabaseCredentials) {
      _supabaseInitializationError = supabaseConfiguration.messageAr;
      return;
    }

    try {
      await Supabase.initialize(
        url: supabaseUrl.trim(),
        publishableKey: supabaseAnonKey.trim(),
      );
      _supabaseInitialized = true;
    } catch (_) {
      _supabaseInitializationError = isProduction
          ? 'تعذر تهيئة الاتصال الآمن بالخادم في نسخة الإنتاج. '
              'راجع إعدادات النشر ثم أعد المحاولة.'
          : 'تعذر تهيئة الاتصال بالخادم. تعمل هذه النسخة في الوضع التجريبي.';
    }
  }
}
