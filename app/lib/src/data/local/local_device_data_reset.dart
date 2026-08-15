import 'local_cache.dart';
import '../sync/sync_outbox.dart';

/// Clears durable device state used by demo, cache, and the outbox.
///
/// This never talks to Supabase and must not be described as a production
/// database wipe.
class LocalDeviceDataReset {
  const LocalDeviceDataReset({
    required this.cache,
    required this.outbox,
  });

  final LocalCache cache;
  final SyncOutbox outbox;

  Future<void> wipeLocalDemoCacheAndOutbox() async {
    await cache.clearAllLocalSnapshots();
    await outbox.clearAllLocalEntries();
  }
}
