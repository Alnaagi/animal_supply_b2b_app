class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.role,
    this.businessName,
    this.customerId,
    this.fullName,
    this.phone,
    this.city,
    this.area,
    this.address,
    this.discountPercent = 0,
    this.creditLimit = 0,
    this.outstandingBalance = 0,
    this.profileActive = true,
    this.mustChangePassword = false,
    this.accountStatus,
    this.isDemo = false,
  });

  final String id;
  final String username;
  final String role;
  final String? businessName;
  final String? customerId;
  final String? fullName;
  final String? phone;
  final String? city;
  final String? area;
  final String? address;
  final double discountPercent;
  final double creditLimit;
  final double outstandingBalance;
  final bool profileActive;
  final bool mustChangePassword;
  final String? accountStatus;
  final bool isDemo;

  bool get isAdmin => role == 'admin';
  bool get isStaff => role == 'staff';
  bool get isAdminLike => role == 'admin' || role == 'staff';
  bool get isCustomer => role == 'customer';
  bool get hasSupportedRole => isAdminLike || isCustomer;
  bool get hasActiveAccount =>
      profileActive && (!isCustomer || accountStatus == 'active');

  AppUser copyWith({
    String? id,
    String? username,
    String? role,
    String? businessName,
    String? customerId,
    String? fullName,
    String? phone,
    String? city,
    String? area,
    String? address,
    double? discountPercent,
    double? creditLimit,
    double? outstandingBalance,
    bool? profileActive,
    bool? mustChangePassword,
    String? accountStatus,
    bool? isDemo,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      role: role ?? this.role,
      businessName: businessName ?? this.businessName,
      customerId: customerId ?? this.customerId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      area: area ?? this.area,
      address: address ?? this.address,
      discountPercent: discountPercent ?? this.discountPercent,
      creditLimit: creditLimit ?? this.creditLimit,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      profileActive: profileActive ?? this.profileActive,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      accountStatus: accountStatus ?? this.accountStatus,
      isDemo: isDemo ?? this.isDemo,
    );
  }
}
