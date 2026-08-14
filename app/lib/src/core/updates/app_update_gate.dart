import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';
import '../config/app_config.dart';
import 'update_link.dart';

class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate>
    with WidgetsBindingObserver {
  bool _checking = false;
  int? _lastCheckedBuild;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_check(force: true));
    }
  }

  String? _platform() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }

  Future<void> _check({bool force = false}) async {
    if (_checking ||
        !mounted ||
        AppConfig.isDemoMode ||
        !AppConfig.remoteBackendEnabled) {
      return;
    }
    final platform = _platform();
    if (platform == null) return;

    _checking = true;
    try {
      final package = await PackageInfo.fromPlatform();
      final installedCode = int.tryParse(package.buildNumber) ?? 0;
      if (!force && _lastCheckedBuild == installedCode) return;
      _lastCheckedBuild = installedCode;

      final version = await ref
          .read(adminRepositoryProvider)
          .latestVersion(platform: platform);
      if (!mounted || !version.hasUpdateFor(installedCode)) return;
      await _showUpdateDialog(version, installedCode);
    } catch (_) {
      // Update checks must never block a usable version when the metadata
      // endpoint is temporarily unavailable.
    } finally {
      _checking = false;
    }
  }

  Future<void> _showUpdateDialog(
    AppVersionInfo version,
    int installedCode,
  ) async {
    final required = version.requiresUpdateFor(installedCode);
    final updateUri = safeHttpsUpdateUri(version.apkUrl);
    // A required update without a valid HTTPS destination must not trap the
    // user in a dialog they can never complete.
    final enforceRequiredUpdate = required && updateUri != null;
    await showDialog<void>(
      context: context,
      barrierDismissible: !enforceRequiredUpdate,
      builder: (dialogContext) => PopScope(
        canPop: !enforceRequiredUpdate,
        child: AlertDialog(
          icon: const Icon(Icons.system_update_alt, size: 42),
          title: Text(required ? 'تحديث مطلوب' : 'يتوفر تحديث جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الإصدار الجديد: ${version.versionName}'),
              if (version.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(version.releaseNotes),
              ],
              if (version.sha256.isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText(
                  'SHA-256: ${version.sha256}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              Text(
                enforceRequiredUpdate
                    ? 'يجب تثبيت النسخة الجديدة للمتابعة بأمان.'
                    : required
                        ? 'بيانات رابط التحديث غير صالحة حالياً. '
                            'تواصل مع إدارة المتجر، ويمكنك المتابعة مؤقتاً.'
                        : 'يمكنك التحديث الآن أو المتابعة مؤقتاً.',
              ),
            ],
          ),
          actions: [
            if (!enforceRequiredUpdate)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('لاحقاً'),
              ),
            FilledButton.icon(
              onPressed: updateUri == null
                  ? null
                  : () async {
                      final opened = await launchUrl(
                        updateUri,
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened || !dialogContext.mounted) return;
                      if (!enforceRequiredUpdate) {
                        Navigator.pop(dialogContext);
                      }
                    },
              icon: const Icon(Icons.download),
              label: const Text('فتح رابط التحديث'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
