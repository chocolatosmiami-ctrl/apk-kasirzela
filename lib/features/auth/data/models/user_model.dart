class UserModel {
  final int? id;
  final String? authId;   // Supabase auth UUID
  final String name;
  final String pinHash;
  final String role;
  final bool isActive;
  final String createdAt;

  const UserModel({
    this.id,
    this.authId,
    required this.name,
    required this.pinHash,
    required this.role,
    this.isActive = true,
    required this.createdAt,
  });

  bool get isSuperAdmin => role == 'superadmin';
  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin' || role == 'owner' || role == 'superadmin';
  bool get isKasir => role == 'kasir';

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as int?,
      authId: map['auth_id'] as String? ?? map['authId'] as String?,
      name: map['name'] as String? ?? 'Pengguna',
      pinHash: map['pin_hash'] as String? ?? map['pin'] as String? ?? '',
      role: map['role'] as String? ?? 'kasir',
      isActive: map['is_active'] == true || (map['is_active'] as int? ?? 1) == 1,
      createdAt: map['created_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (authId != null) 'auth_id': authId,
      'name': name,
      'pin_hash': pinHash,
      'role': role,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
    };
  }

  UserModel copyWith({
    int? id,
    String? authId,
    String? name,
    String? pinHash,
    String? role,
    bool? isActive,
    String? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      authId: authId ?? this.authId,
      name: name ?? this.name,
      pinHash: pinHash ?? this.pinHash,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
