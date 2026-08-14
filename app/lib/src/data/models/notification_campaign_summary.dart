class NotificationCampaignSummary {
  const NotificationCampaignSummary({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.recipientCount,
    required this.completedCount,
    required this.pendingCount,
    required this.retryingCount,
    required this.deadCount,
    required this.deviceSentCount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> audience;
  final int recipientCount;
  final int completedCount;
  final int pendingCount;
  final int retryingCount;
  final int deadCount;
  final int deviceSentCount;
  final DateTime createdAt;

  bool get hasDeliveryProblems => retryingCount > 0 || deadCount > 0;

  factory NotificationCampaignSummary.fromSupabase(
    Map<String, dynamic> row,
  ) {
    final audience = row['audience'];
    return NotificationCampaignSummary(
      id: (row['campaign_id'] ?? row['id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      body: (row['body'] ?? '').toString(),
      audience: audience is Map
          ? Map<String, dynamic>.from(audience)
          : const <String, dynamic>{},
      recipientCount: _integer(row['recipient_count']),
      completedCount: _integer(row['completed_count']),
      pendingCount: _integer(row['pending_count']),
      retryingCount: _integer(row['retrying_count']),
      deadCount: _integer(row['dead_count']),
      deviceSentCount: _integer(row['device_sent_count']),
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  static int _integer(dynamic value) => (value as num?)?.toInt() ?? 0;
}
