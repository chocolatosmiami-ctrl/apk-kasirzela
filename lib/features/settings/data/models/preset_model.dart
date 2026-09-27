import 'package:flutter/material.dart';

class PresetModel {
  final int? id;
  final String name;
  final String emoji;
  final Color color;
  final List<String> permissions;
  final bool isDefault;
  final int sortOrder;

  const PresetModel({
    this.id,
    required this.name,
    required this.emoji,
    required this.color,
    required this.permissions,
    this.isDefault = false,
    this.sortOrder = 0,
  });

  factory PresetModel.fromMap(Map<String, dynamic> map) {
    final permsStr = map['permissions'] as String? ?? '';
    return PresetModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      emoji: map['emoji'] as String? ?? '📋',
      color: Color(map['color'] as int? ?? 0xFF1565C0),
      permissions: permsStr.isEmpty ? [] : permsStr.split(','),
      isDefault: (map['is_default'] as int? ?? 0) == 1,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'emoji': emoji,
    'color': color.value,
    'permissions': permissions.join(','),
    'is_default': isDefault ? 1 : 0,
    'sort_order': sortOrder,
  };

  bool hasPermission(String perm) => permissions.contains(perm);

  PresetModel copyWith({
    int? id, String? name, String? emoji,
    Color? color, List<String>? permissions,
    bool? isDefault, int? sortOrder,
  }) => PresetModel(
    id: id ?? this.id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    color: color ?? this.color,
    permissions: permissions ?? this.permissions,
    isDefault: isDefault ?? this.isDefault,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}
