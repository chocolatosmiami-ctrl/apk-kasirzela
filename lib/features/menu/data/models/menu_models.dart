class CategoryModel {
  final int? id;
  final String name;
  final String icon;
  final int sortOrder;
  final bool isActive;

  const CategoryModel({
    this.id,
    required this.name,
    required this.icon,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      icon: map['icon'] as String? ?? '🍽️',
      sortOrder: map['sort_order'] as int? ?? 0,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'icon': icon,
      'sort_order': sortOrder,
      'is_active': isActive ? 1 : 0,
    };
  }

  CategoryModel copyWith({int? id, String? name, String? icon, int? sortOrder, bool? isActive}) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }
}

class MenuItemModel {
  final int? id;
  final int categoryId;
  final String? branchId;  // null = semua cabang (global)
  final String name;
  final String? description;
  final double price;
  final String? imagePath;
  final bool isActive;
  final bool hasStock;
  final int stock;
  final String? unit;
  final String createdAt;
  final int sortOrder;

  // For joined queries
  final String? categoryName;
  final String? categoryIcon;

  const MenuItemModel({
    this.id,
    required this.categoryId,
    this.branchId,
    required this.name,
    this.description,
    required this.price,
    this.imagePath,
    this.isActive = true,
    this.hasStock = false,
    this.stock = 0,
    this.unit,
    required this.createdAt,
    this.sortOrder = 0,
    this.categoryName,
    this.categoryIcon,
  });

  bool get isAvailable => isActive && (!hasStock || stock > 0);

  factory MenuItemModel.fromMap(Map<String, dynamic> map) {
    return MenuItemModel(
      id: map['id'] as int?,
      categoryId: (map['category_id'] as num?)?.toInt() ?? 0,
      branchId: map['branch_id'] as String?,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      imagePath: map['image_path'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      hasStock: (map['has_stock'] as int? ?? 0) == 1,
      stock: map['stock'] as int? ?? 0,
      unit: map['unit'] as String?,
      createdAt: map['created_at'] as String? ?? DateTime.now().toIso8601String(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      categoryName: map['category_name'] as String?,
      categoryIcon: map['category_icon'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'category_id': categoryId,
      // BUG 57 FIX: branch_id wajib disertakan agar tidak di-null-kan saat update.
      if (branchId != null) 'branch_id': branchId,
      'name': name,
      'description': description,
      'price': price,
      'image_path': imagePath,
      'is_active': isActive ? 1 : 0,
      'has_stock': hasStock ? 1 : 0,
      'stock': stock,
      if (unit != null) 'unit': unit,
      'sort_order': sortOrder,
      'created_at': createdAt,
    };
  }

  MenuItemModel copyWith({
    int? id, int? categoryId, String? name, String? description,
    double? price, String? imagePath, bool? isActive, bool? hasStock,
    int? stock, String? createdAt, String? categoryName, String? categoryIcon,
  }) {
    return MenuItemModel(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imagePath: imagePath ?? this.imagePath,
      isActive: isActive ?? this.isActive,
      hasStock: hasStock ?? this.hasStock,
      stock: stock ?? this.stock,
      createdAt: createdAt ?? this.createdAt,
      categoryName: categoryName ?? this.categoryName,
      categoryIcon: categoryIcon ?? this.categoryIcon,
    );
  }
}