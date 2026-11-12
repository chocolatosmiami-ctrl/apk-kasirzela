/// New receipts have an explicit offset; old SQLite receipts used WIB without
/// an offset. SQLite DATE(offset_timestamp) alone converts to UTC and hides
/// 00:00-06:59 WIB sales from today's history.
const orderWibDateSql = '''
CASE WHEN upper(substr(o.created_at, -1)) = 'Z'
  OR o.created_at GLOB '*[+-][0-9][0-9]:[0-9][0-9]'
THEN DATE(o.created_at, '+7 hours')
ELSE substr(o.created_at, 1, 10) END
''';

/// Outbox rows remain after acknowledgement, preserving member reprint data.
/// The JSON is parsed in Dart, so no SQLite JSON extension/schema change is needed.
const orderReceiptMemberSql = '''
(SELECT receipt_q.payload FROM order_sync_outbox receipt_q
 WHERE receipt_q.order_id = o.id AND receipt_q.account_id = o.cashier_id
   AND receipt_q.branch_id = o.branch_id
 ORDER BY receipt_q.id DESC LIMIT 1) AS receipt_member_payload
''';
