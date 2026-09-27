class ExpenseModel {
  final int? id;
  final String category;
  final String description;
  final double amount;
  final String date;
  final String? cashierId;
  final String createdAt;

  const ExpenseModel({
    this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
    this.cashierId,
    required this.createdAt,
  });

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    return ExpenseModel(
      id: map['id'] as int?,
      category: map['category'] as String,
      description: map['description'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: map['date'] as String,
      cashierId: map['cashier_id']?.toString(),
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'category': category,
    'description': description,
    'amount': amount,
    'date': date,
    'cashier_id': cashierId,
    'created_at': createdAt,
  };

  static const List<String> categories = [
    'Bahan Baku',
    'Gaji Karyawan',
    'Listrik & Air',
    'Sewa Tempat',
    'Peralatan',
    'Transportasi',
    'Kebersihan',
    'Lain-lain',
  ];
}
