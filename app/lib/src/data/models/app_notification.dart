class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.payload = const <String, dynamic>{},
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;
  String? get orderId => payload['order_id']?.toString();
  String? get productId => payload['product_id']?.toString();

  AppNotification copyWith({DateTime? readAt}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      payload: payload,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  factory AppNotification.fromSupabase(Map<String, dynamic> row) {
    final payload = row['payload'];
    return AppNotification(
      id: row['id'].toString(),
      type: (row['type'] ?? 'general').toString(),
      title: (row['title'] ?? '').toString(),
      body: (row['body'] ?? '').toString(),
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now(),
      readAt: row['read_at'] == null
          ? null
          : DateTime.tryParse(row['read_at'].toString()),
    );
  }
}
