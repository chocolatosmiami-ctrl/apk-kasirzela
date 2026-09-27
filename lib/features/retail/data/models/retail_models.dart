// ── Retail Product Model ──────────────────────────────────
class RetailProduct {
  final int? id;
  final String name;
  final String sku;
  final String? barcode;
  final String category;
  final double sellPrice;    // Harga jual
  final double hpp;          // Harga Pokok Penjualan
  final double stock;        // Stok saat ini
  final double minStock;     // Minimum stok (alert)
  final String unit;         // Satuan utama: pcs, kg, gram, liter, dll
  final bool isByWeight;     // true = jual per gram/kg (kiloan)
  final String? imagePath;
  final bool isActive;
  final String createdAt;

  // Multi satuan
  final List<ProductUnit>? units; // satuan konversi (lusin, karton, dll)

  const RetailProduct({
    this.id,
    required this.name,
    required this.sku,
    this.barcode,
    required this.category,
    required this.sellPrice,
    required this.hpp,
    required this.stock,
    this.minStock = 5,
    required this.unit,
    this.isByWeight = false,
    this.imagePath,
    this.isActive = true,
    required this.createdAt,
    this.units,
  });

  bool get isLowStock => stock <= minStock;
  bool get isOutOfStock => stock <= 0;
  double get profitMargin => sellPrice > 0 ? ((sellPrice - hpp) / sellPrice * 100) : 0;
  double get profitPerUnit => sellPrice - hpp;

  factory RetailProduct.fromMap(Map<String, dynamic> map) {
    return RetailProduct(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      sku: map['sku'] as String? ?? '',
      barcode: map['barcode'] as String?,
      category: map['category'] as String? ?? 'Umum',
      sellPrice: (map['sell_price'] as num?)?.toDouble() ?? 0,
      hpp: (map['hpp'] as num?)?.toDouble() ?? 0,
      stock: (map['stock'] as num?)?.toDouble() ?? 0,
      minStock: (map['min_stock'] as num?)?.toDouble() ?? 5,
      unit: map['unit'] as String? ?? 'pcs',
      isByWeight: (map['is_by_weight'] as int?) == 1,
      imagePath: map['image_path'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'sku': sku,
    'barcode': barcode,
    'category': category,
    'sell_price': sellPrice,
    'hpp': hpp,
    'stock': stock,
    'min_stock': minStock,
    'unit': unit,
    'is_by_weight': isByWeight ? 1 : 0,
    'image_path': imagePath,
    'is_active': isActive ? 1 : 0,
    'created_at': createdAt,
  };

  RetailProduct copyWith({
    double? stock,
    double? sellPrice,
    double? hpp,
    bool? isActive,
  }) => RetailProduct(
    id: id, name: name, sku: sku, barcode: barcode,
    category: category,
    sellPrice: sellPrice ?? this.sellPrice,
    hpp: hpp ?? this.hpp,
    stock: stock ?? this.stock,
    minStock: minStock, unit: unit,
    isByWeight: isByWeight, imagePath: imagePath,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
  );
}

// ── Multi Unit Conversion ─────────────────────────────────
class ProductUnit {
  final int? id;
  final int productId;
  final String unitName;   // lusin, karton, pack
  final double conversion; // 1 lusin = 12 pcs
  final double sellPrice;  // harga per unit ini

  const ProductUnit({
    this.id,
    required this.productId,
    required this.unitName,
    required this.conversion,
    required this.sellPrice,
  });

  factory ProductUnit.fromMap(Map<String, dynamic> map) => ProductUnit(
    id: map['id'] as int?,
    productId: map['product_id'] as int? ?? 0,
    unitName: map['unit_name'] as String? ?? '',
    conversion: (map['conversion'] as num?)?.toDouble() ?? 1,
    sellPrice: (map['sell_price'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'product_id': productId,
    'unit_name': unitName,
    'conversion': conversion,
    'sell_price': sellPrice,
  };
}

// ── Stock Movement ────────────────────────────────────────
class StockMovement {
  final int? id;
  final int productId;
  final String productName;
  final String type;       // 'in' | 'out' | 'adjustment' | 'sale'
  final double qty;
  final double stockBefore;
  final double stockAfter;
  final String? note;
  final String createdAt;
  final String? createdBy;

  const StockMovement({
    this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.qty,
    required this.stockBefore,
    required this.stockAfter,
    this.note,
    required this.createdAt,
    this.createdBy,
  });

  factory StockMovement.fromMap(Map<String, dynamic> map) => StockMovement(
    id: map['id'] as int?,
    productId: map['product_id'] as int? ?? 0,
    productName: map['product_name'] as String? ?? '',
    type: map['type'] as String? ?? 'in',
    qty: (map['qty'] as num?)?.toDouble() ?? 0,
    stockBefore: (map['stock_before'] as num?)?.toDouble() ?? 0,
    stockAfter: (map['stock_after'] as num?)?.toDouble() ?? 0,
    note: map['note'] as String?,
    createdAt: map['created_at'] as String? ?? '',
    createdBy: map['created_by'] as String?,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'product_id': productId,
    'product_name': productName,
    'type': type,
    'qty': qty,
    'stock_before': stockBefore,
    'stock_after': stockAfter,
    'note': note,
    'created_at': createdAt,
    'created_by': createdBy,
  };
}

// ── Retail Cart Item ──────────────────────────────────────
class RetailCartItem {
  final RetailProduct product;
  final double qty;         // bisa desimal untuk kiloan
  final String selectedUnit; // unit yang dipilih (pcs/lusin/kg/gram)
  final double unitPrice;   // harga sesuai unit dipilih
  final double discount;    // diskon per item

  const RetailCartItem({
    required this.product,
    required this.qty,
    required this.selectedUnit,
    required this.unitPrice,
    this.discount = 0,
  });

  double get subtotal => (unitPrice * qty) - discount;
  double get hppTotal => product.hpp * qty;

  RetailCartItem copyWith({double? qty, double? discount}) => RetailCartItem(
    product: product,
    qty: qty ?? this.qty,
    selectedUnit: selectedUnit,
    unitPrice: unitPrice,
    discount: discount ?? this.discount,
  );
}

// ── Branch Mode ───────────────────────────────────────────
enum BranchMode { food, retail }

extension BranchModeExt on BranchMode {
  String get label => this == BranchMode.food ? 'Rumah Makan' : 'Retail / Toko';
  String get emoji => this == BranchMode.food ? '🍽️' : '🛍️';
  String get value => this == BranchMode.food ? 'food' : 'retail';

  static BranchMode fromString(String? s) =>
      s?.toLowerCase() == 'retail' ? BranchMode.retail : BranchMode.food;
}
