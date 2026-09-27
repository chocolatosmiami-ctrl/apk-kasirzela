class IngredientModel {
  final int? id;
  final String name;
  final String unit; // kg, gram, liter, pcs, dll
  final double currentStock;
  final double minStock; // alert when below this
  final String? notes;
  final String updatedAt;

  const IngredientModel({
    this.id,
    required this.name,
    required this.unit,
    required this.currentStock,
    required this.minStock,
    this.notes,
    required this.updatedAt,
  });

  bool get isLow => currentStock <= minStock;
  bool get isOut => currentStock <= 0;

  factory IngredientModel.fromMap(Map<String, dynamic> map) {
    return IngredientModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      unit: map['unit'] as String,
      currentStock: (map['current_stock'] as num).toDouble(),
      minStock: (map['min_stock'] as num).toDouble(),
      notes: map['notes'] as String?,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'unit': unit,
    'current_stock': currentStock,
    'min_stock': minStock,
    'notes': notes,
    'updated_at': updatedAt,
  };

  IngredientModel copyWith({
    int? id, String? name, String? unit,
    double? currentStock, double? minStock,
    String? notes, String? updatedAt,
  }) => IngredientModel(
    id: id ?? this.id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    currentStock: currentStock ?? this.currentStock,
    minStock: minStock ?? this.minStock,
    notes: notes ?? this.notes,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static const List<String> units = [
    'kg', 'gram', 'ons',
    'liter', 'ml',
    'pcs', 'porsi', 'bungkus', 'dus',
    'ikat', 'butir', 'buah',
  ];
}

// Link antara menu item dan bahan baku
class MenuIngredientModel {
  final int? id;
  final int menuItemId;
  final int ingredientId;
  final double quantityUsed; // berapa bahan terpakai per 1 porsi
  final String ingredientName; // for display
  final String unit;

  const MenuIngredientModel({
    this.id,
    required this.menuItemId,
    required this.ingredientId,
    required this.quantityUsed,
    this.ingredientName = '',
    this.unit = '',
  });

  factory MenuIngredientModel.fromMap(Map<String, dynamic> map) {
    return MenuIngredientModel(
      id: map['id'] as int?,
      menuItemId: map['menu_item_id'] as int,
      ingredientId: map['ingredient_id'] as int,
      quantityUsed: (map['quantity_used'] as num).toDouble(),
      ingredientName: map['ingredient_name'] as String? ?? '',
      unit: map['unit'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'menu_item_id': menuItemId,
    'ingredient_id': ingredientId,
    'quantity_used': quantityUsed,
  };
}
