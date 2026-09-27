enum TableStatus { empty, occupied, bill, reserved }

extension TableStatusExt on TableStatus {
  String get label {
    switch (this) {
      case TableStatus.empty: return 'Kosong';
      case TableStatus.occupied: return 'Terisi';
      case TableStatus.bill: return 'Minta Bill';
      case TableStatus.reserved: return 'Reservasi';
    }
  }

  String get emoji {
    switch (this) {
      case TableStatus.empty: return '🟢';
      case TableStatus.occupied: return '🔴';
      case TableStatus.bill: return '🟡';
      case TableStatus.reserved: return '🔵';
    }
  }

  static TableStatus fromString(String? s) {
    switch (s) {
      case 'occupied': return TableStatus.occupied;
      case 'bill': return TableStatus.bill;
      case 'reserved': return TableStatus.reserved;
      default: return TableStatus.empty;
    }
  }
}

class TableModel {
  final int? id;
  final String name;       // "Meja 1", "VIP 1", "Teras A"
  final String zone;       // "Dalam", "Luar", "VIP"
  final int capacity;      // jumlah kursi
  final TableStatus status;
  final int? activeOrderId;
  final String? customerName;
  final String? reservedAt;
  final String? occupiedAt;
  final bool isActive;

  const TableModel({
    this.id,
    required this.name,
    this.zone = 'Dalam',
    this.capacity = 4,
    this.status = TableStatus.empty,
    this.activeOrderId,
    this.customerName,
    this.reservedAt,
    this.occupiedAt,
    this.isActive = true,
  });

  bool get isEmpty => status == TableStatus.empty;
  bool get isOccupied => status == TableStatus.occupied;
  bool get needsBill => status == TableStatus.bill;

  factory TableModel.fromMap(Map<String, dynamic> map) => TableModel(
    id: map['id'] as int?,
    name: map['name'] as String? ?? '',
    zone: map['zone'] as String? ?? 'Dalam',
    capacity: map['capacity'] as int? ?? 4,
    status: TableStatusExt.fromString(map['status'] as String?),
    activeOrderId: map['active_order_id'] as int?,
    customerName: map['customer_name'] as String?,
    reservedAt: map['reserved_at'] as String?,
    occupiedAt: map['occupied_at'] as String?,
    isActive: (map['is_active'] as int? ?? 1) == 1,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'zone': zone,
    'capacity': capacity,
    'status': status.name,
    'active_order_id': activeOrderId,
    'customer_name': customerName,
    'reserved_at': reservedAt,
    'occupied_at': occupiedAt,
    'is_active': isActive ? 1 : 0,
  };

  TableModel copyWith({
    TableStatus? status,
    int? activeOrderId,
    String? customerName,
    String? occupiedAt,
  }) => TableModel(
    id: id, name: name, zone: zone, capacity: capacity,
    status: status ?? this.status,
    activeOrderId: activeOrderId ?? this.activeOrderId,
    customerName: customerName ?? this.customerName,
    reservedAt: reservedAt,
    occupiedAt: occupiedAt ?? this.occupiedAt,
    isActive: isActive,
  );
}
