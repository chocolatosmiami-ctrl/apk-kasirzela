/// New receipts have an explicit offset; old SQLite receipts used WIB without
/// an offset. SQLite DATE(offset_timestamp) alone converts to UTC and hides
/// 00:00-06:59 WIB sales from today's history.
const orderWibDateSql = '''
CASE WHEN upper(substr(o.created_at, -1)) = 'Z'
  OR o.created_at GLOB '*[+-][0-9][0-9]:[0-9][0-9]'
THEN DATE(o.created_at, '+7 hours')
ELSE substr(o.created_at, 1, 10) END
''';
