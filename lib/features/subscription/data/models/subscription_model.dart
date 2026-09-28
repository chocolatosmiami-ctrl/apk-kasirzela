class SubscriptionModel {
  final String branchId;
  final String branchName;
  final double balance;
  final int totalTransactions;
  final double costPerTransaction; // dari DB: cost_per_trx
  final bool isLocked;
  final DateTime? lastTopUp;
  final DateTime? lockedAt;

  // Plan fields
  final String planType;           // 'per_trx' | 'monthly' | 'yearly'
  final DateTime? planStartedAt;
  final DateTime? planExpiresAt;
  final double? planPrice;

  const SubscriptionModel({
    required this.branchId,
    required this.branchName,
    required this.balance,
    required this.totalTransactions,
    this.costPerTransaction = 300,
    this.isLocked = false,
    this.lastTopUp,
    this.lockedAt,
    this.planType = 'per_trx',
    this.planStartedAt,
    this.planExpiresAt,
    this.planPrice,
  });

  bool get isActive => !isLocked && (isPlanActive || balance > 0);
  bool get isWarning => planType == 'per_trx' && balance <= 15000 && balance > 0;
  bool get isEmpty => planType == 'per_trx' && balance <= 0;

  /// Plan aktif = monthly/yearly dan belum expired
  bool get isPlanActive {
    if (planType == 'per_trx') return false;
    if (planExpiresAt == null) return false;
    return planExpiresAt!.isAfter(DateTime.now());
  }

  /// Sisa transaksi — hanya relevan untuk plan per_trx
  int get remainingTransactions =>
      isPlanActive ? 999999 : (balance / costPerTransaction).floor();

  /// Label plan untuk ditampilkan di UI
  String get planLabel {
    switch (planType) {
      case 'monthly': return isPlanActive ? '📅 Bulanan (Aktif)' : '📅 Bulanan (Expired)';
      case 'yearly':  return isPlanActive ? '🏆 Tahunan (Aktif)' : '🏆 Tahunan (Expired)';
      default:        return '⚡ Per Transaksi';
    }
  }

  factory SubscriptionModel.fromMap(Map<String, dynamic> map) {
    return SubscriptionModel(
      branchId: map['branch_id'] as String? ?? '',
      branchName: map['branch_name'] as String? ?? '',
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      totalTransactions: map['total_transactions'] as int? ?? 0,
      // Kolom di DB: cost_per_trx
      costPerTransaction: (map['cost_per_trx'] as num?)?.toDouble() ??
          (map['cost_per_transaction'] as num?)?.toDouble() ?? 300,
      isLocked: map['is_locked'] as bool? ?? false,
      lastTopUp: map['last_top_up'] != null
          ? DateTime.tryParse(map['last_top_up'] as String)
          : null,
      lockedAt: map['locked_at'] != null
          ? DateTime.tryParse(map['locked_at'] as String)
          : null,
      planType: map['plan_type'] as String? ?? 'per_trx',
      planStartedAt: map['plan_started_at'] != null
          ? DateTime.tryParse(map['plan_started_at'] as String)
          : null,
      planExpiresAt: map['plan_expires_at'] != null
          ? DateTime.tryParse(map['plan_expires_at'] as String)
          : null,
      planPrice: (map['plan_price'] as num?)?.toDouble(),
    );
  }

  SubscriptionModel copyWith({
    String? branchId,
    String? branchName,
    double? balance,
    int? totalTransactions,
    double? costPerTransaction,
    bool? isLocked,
    DateTime? lastTopUp,
    DateTime? lockedAt,
    String? planType,
    DateTime? planStartedAt,
    DateTime? planExpiresAt,
    double? planPrice,
  }) {
    return SubscriptionModel(
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      balance: balance ?? this.balance,
      totalTransactions: totalTransactions ?? this.totalTransactions,
      costPerTransaction: costPerTransaction ?? this.costPerTransaction,
      isLocked: isLocked ?? this.isLocked,
      lastTopUp: lastTopUp ?? this.lastTopUp,
      lockedAt: lockedAt ?? this.lockedAt,
      planType: planType ?? this.planType,
      planStartedAt: planStartedAt ?? this.planStartedAt,
      planExpiresAt: planExpiresAt ?? this.planExpiresAt,
      planPrice: planPrice ?? this.planPrice,
    );
  }

  Map<String, dynamic> toMap() => {
    'branch_id': branchId,
    'branch_name': branchName,
    'balance': balance,
    'total_transactions': totalTransactions,
    'cost_per_trx': costPerTransaction,
    'is_locked': isLocked,
    'last_top_up': lastTopUp?.toIso8601String(),
    'locked_at': lockedAt?.toIso8601String(),
    'plan_type': planType,
    'plan_started_at': planStartedAt?.toIso8601String(),
    'plan_expires_at': planExpiresAt?.toIso8601String(),
    'plan_price': planPrice,
  };
}

class TopUpRequest {
  final String id;
  final String branchId;
  final String branchName;
  final double amount;
  final String method;
  final String status;
  final String? proofUrl;
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

  bool get isPending  => status == 'pending';
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