import '../../../menu/data/models/menu_models.dart';

class CartItem {
  final MenuItemModel menuItem;
  int qty;
  String? note;

  CartItem({
    required this.menuItem,
    this.qty = 1,
    this.note,
  });

  double get subtotal => menuItem.price * qty;

  CartItem copyWith({int? qty, String? note}) {
    return CartItem(
      menuItem: menuItem,
      qty: qty ?? this.qty,
      note: note ?? this.note,
    );
  }
}

class OrderModel {
  final int? id;
  final String orderNumber;
  final String? tableNumber;
  final String orderType;
  String status;
  final double subtotal;
  final String discountType; // 'none', 'percent', 'nominal'
  final double discountValue;
  final double discountAmount;
  final double taxPercent;
  final double taxAmount;
  final double serviceChargeAmount; // servis charge nominal
  final double total;
  final String? paymentMethod;
  final double paidAmount;
  final double changeAmount;
  final String? cashierId;
  final String? cashierName;
  final String? note;
  final String? cancelReason;
  final String createdAt;
  final String updatedAt;
  List<OrderItemModel> items;

  OrderModel({
    this.id,
    required this.orderNumber,
    this.tableNumber,
    this.orderType = 'dine_in',
    this.status = 'new',
    this.subtotal = 0,
    this.discountType = 'none',
    this.discountValue = 0,
    this.discountAmount = 0,
    this.taxPercent = 0,
    this.taxAmount = 0,
    this.serviceChargeAmount = 0,
    this.total = 0,
    this.paymentMethod,
    this.paidAmount = 0,
    this.changeAmount = 0,
    this.cashierId,
    this.cashierName,
    this.note,
    this.cancelReason,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  bool get isPaid => status == 'paid';
  bool get isCancelled => status == 'cancelled';

  factory OrderModel.fromMap(Map<String, dynamic> map, {List<OrderItemModel>? items}) {
    return OrderModel(
      id: map['id'] as int?,
      orderNumber: map['order_number'] as String? ?? map['id']?.toString() ?? '',
      tableNumber: map['table_number'] as String?,
      orderType: map['order_type'] as String? ?? 'dine_in',
      status: map['status'] as String? ?? 'completed',
      subtotal: (map['subtotal'] ?? map['total_amount'] ?? map['total'] as num?)?.toDouble() ?? 0,
      discountType: map['discount_type'] as String? ?? 'none',
      discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      taxPercent: (map['tax_percent'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
      serviceChargeAmount: (map['service_charge_amount'] as num?)?.toDouble() ?? 0,
      total: (map['total'] ?? map['total_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: map['payment_method'] as String?,
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
      changeAmount: (map['change_amount'] as num?)?.toDouble() ?? 0,
      cashierId: map['cashier_id']?.toString(),
      cashierName: map['cashier_name'] as String?,
      note: map['note'] as String?,
      cancelReason: map['cancel_reason'] as String?,
      createdAt: map['created_at'] as String? ?? DateTime.now().toIso8601String(),
      updatedAt: map['updated_at'] as String? ?? DateTime.now().toIso8601String(),
      items: items ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'order_number': orderNumber,
      'table_number': tableNumber,
      'order_type': orderType,
      'status': status,
      'subtotal': subtotal,
      'discount_type': discountType,
      'discount_value': discountValue,
      'discount_amount': discountAmount,
      'tax_percent': taxPercent,
      'tax_amount': taxAmount,
      'total': total,
      'payment_method': paymentMethod,
      'paid_amount': paidAmount,
      'change_amount': changeAmount,
      'cashier_id': cashierId,
      'note': note,
      'cancel_reason': cancelReason,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class OrderItemModel {
  final int? id;
  final int orderId;
  final int menuItemId;
  final String name;
  final double price;
  final double qty;
  final String? unit;
  final String? note;
  final double subtotal;

  const OrderItemModel({
    this.id,
    required this.orderId,
    required this.menuItemId,
    required this.name,
    required this.price,
    required this.qty,
    this.unit,
    this.note,
    required this.subtotal,
  });

  factory OrderItemModel.fromMap(Map<String, dynamic> map) {
    return OrderItemModel(
      id: map['id'] as int?,
      orderId: map['order_id'] as int,
      menuItemId: map['menu_item_id'] as int,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      qty: (map['qty'] as num?)?.toDouble() ?? 1.0,
      unit: map['unit'] as String?,
      note: map['note'] as String?,
      subtotal: (map['subtotal'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'order_id': orderId,
      'menu_item_id': menuItemId,
      'name': name,
      'price': price,
      'qty': qty,
      'unit': unit,
      'note': note,
      'subtotal': subtotal,
    };
  }
}