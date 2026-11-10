import '../lib/features/table_management/data/models/table_model.dart';
void main() {
  final table = TableModel.fromMap({'id': 14, 'server_id': 74, 'name': 'VIP A',
    'branch_id': 'branch-a', 'status': 'occupied', 'customer_name': 'Guest', 'is_active': 1});
  if (table.id != 14 || table.serverId != 74 || !table.isOccupied) {
    throw StateError('Local/cart ID must remain separate from metadata server ID');
  }
  if (table.copyWith(status: TableStatus.bill).serverId != 74 ||
      table.toMap()['id'] != 14 || table.toMap()['server_id'] != 74) {
    throw StateError('Copies and cache writes must retain both identities');
  }
  print('PASS: table model preserves local ID, server ID and status');
}
