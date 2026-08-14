import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

FirebaseOptions? firebaseOptionsForCurrentPlatform() {
  if (!AppConfig.hasFirebaseBaseConfig) return null;

  if (kIsWeb) {
    if (AppConfig.firebaseWebAppId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: AppConfig.firebaseApiKey,
      appId: AppConfig.firebaseWebAppId,
      messagingSenderId: AppConfig.firebaseMessagingSenderId,
      projectId: AppConfig.firebaseProjectId,
      authDomain: AppConfig.firebaseAuthDomain.isEmpty
          ? null
          : AppConfig.firebaseAuthDomain,
      storageBucket: AppConfig.firebaseStorageBucket.isEmpty
          ? null
          : AppConfig.firebaseStorageBucket,
    );
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      if (AppConfig.firebaseAndroidAppId.isEmpty) return null;
      return FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseAndroidAppId,
        messagingSenderId: AppConfig.firebaseMessagingSenderId,
        projectId: AppConfig.firebaseProjectId,
        storageBucket: AppConfig.firebaseStorageBucket.isEmpty
            ? null
            : AppConfig.firebaseStorageBucket,
      );
    case TargetPlatform.iOS:
      if (AppConfig.firebaseIosAppId.isEmpty) return null;
      return FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseIosAppId,
        messagingSenderId: AppConfig.firebaseMessagingSenderId,
        projectId: AppConfig.firebaseProjectId,
        storageBucket: AppConfig.firebaseStorageBucket.isEmpty
            ? null
            : AppConfig.firebaseStorageBucket,
        iosBundleId: AppConfig.firebaseIosBundleId,
      );
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return null;
  }
}
