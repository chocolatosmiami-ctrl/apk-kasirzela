"""Exercise actual outbox DDL and reservation SQL using SQLite, without Android."""
from pathlib import Path
import re
import sqlite3

root = Path(__file__).resolve().parents[1]
helper = (root / 'lib/core/database/database_helper.dart').read_text(encoding='utf-8')
ddl = re.search(r'CREATE TABLE IF NOT EXISTS order_sync_outbox \(.*?\n      \)', helper, re.S).group()
db = sqlite3.connect(':memory:')
db.execute('CREATE TABLE orders(id INTEGER PRIMARY KEY, synced INTEGER DEFAULT 0)')
db.execute(ddl)
db.execute(ddl)  # Migration is repeatable.

def insert_receipt(order_id, account='a', branch='one'):
    db.execute("INSERT INTO orders(id) VALUES (?)", (order_id,))
    db.execute("""INSERT INTO order_sync_outbox(order_id, account_id, branch_id, payload, created_at)
                  VALUES (?,?,?,?,?)""", (order_id, account, branch, '{}', '2026-10-17T01:00:00Z'))

try:
    with db:
        insert_receipt(1)
        raise RuntimeError('app killed before checkout commit')
except RuntimeError:
    pass
assert db.execute('SELECT COUNT(*) FROM orders').fetchone()[0] == 0
assert db.execute('SELECT COUNT(*) FROM order_sync_outbox').fetchone()[0] == 0

with db:
    insert_receipt(1)
    insert_receipt(2, account='b', branch='two')
try:
    with db:
        db.execute("INSERT INTO order_sync_outbox(order_id,account_id,branch_id,payload,created_at) VALUES(1,'a','one','{}','now')")
except sqlite3.IntegrityError:
    pass
else:
    raise AssertionError('Duplicate outbox receipt accepted')

service = (root / 'lib/core/services/offline_order_sync_service.dart').read_text(encoding='utf-8')
query = re.search(r'SELECT payload FROM order_sync_outbox.*?acknowledged_at >= \?\)', service, re.S).group()
assert len(db.execute(query, ('one','2026-10-17T00:00:00Z')).fetchall()) == 1
with db:
    db.execute("UPDATE order_sync_outbox SET state='done',acknowledged_at='2026-10-17T02:00:00Z' WHERE order_id=1")
# Offline cache captured before online receipt: sale must STILL reduce cached stock.
assert len(db.execute(query, ('one','2026-10-17T01:30:00Z')).fetchall()) == 1
# New server snapshot taken after the acknowledgement: do not subtract twice.
assert len(db.execute(query, ('one','2026-10-17T02:30:00Z')).fetchall()) == 0
assert len(db.execute(query, ('two','2026-10-17T02:30:00Z')).fetchall()) == 1
print('PASS: migration, atomic rollback, durable receipt, duplicate prevention, account/branch fields, online-to-offline cache watermark')
