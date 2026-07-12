class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.role,
    this.businessName,
    this.customerId,
  });

  final String id;
  final String username;
  final String role;
  final String? businessName;
  final String? customerId;

  bool get isAdminLike => role == 'admin' || role == 'staff';
}
