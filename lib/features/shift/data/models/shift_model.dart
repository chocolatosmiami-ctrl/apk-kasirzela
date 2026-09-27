class ShiftModel {
  final int? id;
  final String userId;
  final String userName;
  final String? branchId;
  final String openedAt;
  final String? closedAt;
  final double openingCash;   // modal awal
  final double closingCash;   // uang di laci saat tutup
  final double totalSales;    // total penjualan selama shift
  final double totalCash;     // total bayar tunai
  final double totalNonCash;  // total QRIS/transfer/kartu
  final double totalExpenses; // total pengeluaran selama shift
  final double expectedCash;  // modal + penjualan tunai - pengeluaran
  final double cashDifference;// closingCash - expectedCash (selisih)
  final int totalTransactions;
  final String? notes;
  final String status; // 'open' | 'closed'

  const ShiftModel({
    this.id,
    required this.userId,
    required this.userName,
    this.branchId,
    required this.openedAt,
    this.closedAt,
    required this.openingCash,
    this.closingCash = 0,
    this.totalSales = 0,
    this.totalCash = 0,
    this.totalNonCash = 0,
    this.totalExpenses = 0,
    this.expectedCash = 0,
    this.cashDifference = 0,
    this.totalTransactions = 0,
    this.notes,
    this.status = 'open',
  });

  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';
  bool get hasDifference => cashDifference.abs() > 0;
  bool get isShortage => cashDifference < 0;
  bool get isSurplus => cashDifference > 0;

  Duration get duration {
    final start = DateTime.parse(openedAt);
    final end = closedAt != null ? DateTime.parse(closedAt!) : DateTime.now();
    return end.difference(start);
  }

  String get durationText {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}j ${m}m';
    return '${m}m';
  }

  factory ShiftModel.fromMap(Map<String, dynamic> map) {
    return ShiftModel(
      branchId: map['branch_id']?.toString(),
      id: map['id'] as int?,
      userId: map['user_id']?.toString() ?? '',
      userName: map['user_name']?.toString() ?? '',
      openedAt: map['opened_at']?.toString() ?? DateTime.now().toIso8601String(),
      closedAt: map['closed_at']?.toString(),
      openingCash: (map['opening_cash'] as num? ?? 0).toDouble(),
      closingCash: (map['closing_cash'] as num? ?? 0).toDouble(),
      totalSales: (map['total_sales'] as num? ?? 0).toDouble(),
      totalCash: (map['total_cash'] as num? ?? 0).toDouble(),
      totalNonCash: (map['total_non_cash'] as num? ?? 0).toDouble(),
      totalExpenses: (map['total_expenses'] as num? ?? 0).toDouble(),
      expectedCash: (map['expected_cash'] as num? ?? 0).toDouble(),
      cashDifference: (map['cash_difference'] as num? ?? 0).toDouble(),
      totalTransactions: (map['total_transactions'] as num? ?? 0).toInt(),
      notes: map['notes']?.toString(),
      status: map['status']?.toString() ?? 'open',
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'user_id': userId,
    if (branchId != null) 'branch_id': branchId,
    'user_name': userName,
    'opened_at': openedAt,
    'closed_at': closedAt,
    'opening_cash': openingCash,
    'closing_cash': closingCash,
    'total_sales': totalSales,
    'total_cash': totalCash,
    'total_non_cash': totalNonCash,
    'total_expenses': totalExpenses,
    'expected_cash': expectedCash,
    'cash_difference': cashDifference,
    'total_transactions': totalTransactions,
    'notes': notes,
    'status': status,
  };

  ShiftModel copyWith({
    int? id, int? userId, String? userName,
    String? openedAt, String? closedAt,
    double? openingCash, double? closingCash,
    double? totalSales, double? totalCash, double? totalNonCash,
    double? totalExpenses, double? expectedCash, double? cashDifference,
    int? totalTransactions, String? notes, String? status,
  }) => ShiftModel(
    id: id ?? this.id,
    userId: (userId ?? this.userId).toString(),
    userName: userName ?? this.userName,
    openedAt: openedAt ?? this.openedAt,
    closedAt: closedAt ?? this.closedAt,
    openingCash: openingCash ?? this.openingCash,
    closingCash: closingCash ?? this.closingCash,
    totalSales: totalSales ?? this.totalSales,
    totalCash: totalCash ?? this.totalCash,
    totalNonCash: totalNonCash ?? this.totalNonCash,
    totalExpenses: totalExpenses ?? this.totalExpenses,
    expectedCash: expectedCash ?? this.expectedCash,
    cashDifference: cashDifference ?? this.cashDifference,
    totalTransactions: totalTransactions ?? this.totalTransactions,
    notes: notes ?? this.notes,
    status: status ?? this.status,
  );
}
