class SubscriptionModel {
  final String branchId;
  final String branchName;
  final double balance;           // saldo dalam rupiah
  final int totalTransactions;    // total transaksi yang sudah dilakukan
  final double costPerTransaction; // Rp150 per transaksi
  final bool isLocked;            // terkunci kalau saldo habis
  final DateTime? lastTopUp;
  final DateTime? lockedAt;

  const SubscriptionModel({
    required this.branchId,
    required this.branchName,
    required this.balance,
    required this.totalTransactions,
    this.costPerTransaction = 500,
    this.isLocked = false,
    this.lastTopUp,
    this.lockedAt,
  });

  bool get isActive => balance > 0 && !isLocked;
  bool get isWarning => balance <= 15000 && balance > 0; // warning < 100 trx
  bool get isEmpty => balance <= 0;

  // Estimasi sisa transaksi
  int get remainingTransactions => (balance / costPerTransaction).floor();

  factory SubscriptionModel.fromMap(Map<String, dynamic> map) {
    return SubscriptionModel(
      branchId: map['branch_id'] as String? ?? '',
      branchName: map['branch_name'] as String? ?? '',
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      totalTransactions: map['total_transactions'] as int? ?? 0,
      costPerTransaction: (map['cost_per_transaction'] as num?)?.toDouble() ?? 150,
      isLocked: map['is_locked'] as bool? ?? false,
      lastTopUp: map['last_top_up'] != null
          ? DateTime.tryParse(map['last_top_up'] as String)
          : null,
      lockedAt: map['locked_at'] != null
          ? DateTime.tryParse(map['locked_at'] as String)
          : null,
    );
  }

  SubscriptionModel copyWith({
    String? branchId,
    String? branchName,
    double? balance,
    int? totalTransactions,
    bool? isLocked,
  }) {
    return SubscriptionModel(
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      balance: balance ?? this.balance,
      totalTransactions: totalTransactions ?? this.totalTransactions,
      costPerTransaction: this.costPerTransaction,
      isLocked: isLocked ?? this.isLocked,
      lastTopUp: this.lastTopUp,
      lockedAt: this.lockedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'branch_id': branchId,
    'branch_name': branchName,
    'balance': balance,
    'total_transactions': totalTransactions,
    'cost_per_transaction': costPerTransaction,
    'is_locked': isLocked,
    'last_top_up': lastTopUp?.toIso8601String(),
    'locked_at': lockedAt?.toIso8601String(),
  };
}

class TopUpRequest {
  final String id;
  final String branchId;
  final String branchName;
  final double amount;
  final String method;      // 'transfer' | 'qris'
  final String status;      // 'pending' | 'approved' | 'rejected'
  final String? proofUrl;   // bukti transfer
  final String? notes;
  final DateTime createdAt;
  final DateTime? processedAt;
  final String? processedBy;

  const TopUpRequest({
    required this.id,
    required this.branchId,
    required this.branchName,
    required this.amount,
    required this.method,
    required this.status,
    this.proofUrl,
    this.notes,
    required this.createdAt,
    this.processedAt,
    this.processedBy,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory TopUpRequest.fromMap(String id, Map<String, dynamic> map) {
    return TopUpRequest(
      id: id,
      branchId: map['owner_id'] as String? ?? map['branch_id'] as String? ?? '',
      branchName: map['owner_name'] as String? ?? map['branch_name'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      method: map['method'] as String? ?? 'transfer',
      status: map['status'] as String? ?? 'pending',
      proofUrl: map['proof_url'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      processedAt: map['processed_at'] != null
          ? DateTime.tryParse(map['processed_at'] as String)
          : null,
      processedBy: map['processed_by'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'branch_id': branchId,
    'branch_name': branchName,
    'amount': amount,
    'method': method,
    'status': status,
    'proof_url': proofUrl,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'processed_at': processedAt?.toIso8601String(),
    'processed_by': processedBy,
  };
}
