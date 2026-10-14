/// Which irreversible reset actions the settings danger card may show.
class AdminDataResetVisibility {
  const AdminDataResetVisibility({
    required this.demoMode,
    required this.productionBackendLive,
  });

  /// Local demo overlay, demo build, or unconfigured backend fallback.
  final bool demoMode;

  /// Production/staging Supabase is initialized and the demo overlay is off.
  final bool productionBackendLive;

  bool get showDemoLocalReset => demoMode;

  bool get showProductionRemoteReset => !demoMode && productionBackendLive;

  bool get showLocalCacheOnlyReset => !demoMode && productionBackendLive;
}
