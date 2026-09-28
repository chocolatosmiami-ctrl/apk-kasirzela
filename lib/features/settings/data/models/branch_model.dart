class BranchModel {
  final int? id;
  final String name;
  final String? address;
  final String? phone;
  final String mode; // 'food' | 'retail'
  final bool isActive;
  final bool isCurrent;
  final String createdAt;

  const BranchModel({
    this.id,
    required this.name,
    this.address,
    this.phone,
    this.mode = 'food',
    this.isActive = true,
    this.isCurrent = false,
    required this.createdAt,
  });

  bool get isRetail => mode == 'retail';

  factory BranchModel.fromMap(Map<String, dynamic> map) => BranchModel(
    id: map['id'] as int?,
    name: map['name'] as String,
    address: map['address'] as String?,
    phone: map['phone'] as String?,
    mode: map['mode'] as String? ?? 'food',
    isActive: (map['is_active'] as int) == 1,
    isCurrent: (map['is_current'] as int) == 1,
    createdAt: map['created_at'] as String,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'address': address,
    'phone': phone,
    'is_active': isActive ? 1 : 0,
    'is_current': isCurrent ? 1 : 0,
    'created_at': createdAt,
  };

  BranchModel copyWith({
    int? id, String? name, String? address,
    String? phone, bool? isActive, bool? isCurrent, String? createdAt,
  }) => BranchModel(
    id: id ?? this.id,
    name: name ?? this.name,
    address: address ?? this.address,
    phone: phone ?? this.phone,
    isActive: isActive ?? this.isActive,
    isCurrent: isCurrent ?? this.isCurrent,
    createdAt: createdAt ?? this.createdAt,
  );
}
