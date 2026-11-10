from pathlib import Path
import re
import sqlite3

source = (Path(__file__).resolve().parents[1] / 'lib/core/database/order_queries.dart').read_text()
expression = re.search(r"const orderWibDateSql = '''(.*?)''';", source, re.S).group(1)
db = sqlite3.connect(':memory:')
db.execute('CREATE TABLE orders(created_at TEXT)')
cases = [
    ('2026-10-30T05:40:00.000+07:00', '2026-10-30'),
    ('2026-10-29T22:40:00.000Z', '2026-10-30'),
    ('2026-10-30T00:00:00.000+07:00', '2026-10-30'),
    ('2026-10-29T23:59:59.999+07:00', '2026-10-29'),
    ('2026-10-30T23:59:00.000', '2026-10-30'),
    ('2026-10-30 05:40:00', '2026-10-30'),
]
for timestamp, expected in cases:
    db.execute('DELETE FROM orders')
    db.execute('INSERT INTO orders VALUES (?)', [timestamp])
    actual = db.execute(f'SELECT {expression} FROM orders o').fetchone()[0]
    assert actual == expected, (timestamp, actual, expected)
print('PASS: SQLite history at WIB midnight, early morning, UTC input, legacy naive timestamp')
