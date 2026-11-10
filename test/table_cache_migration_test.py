import re
import sqlite3
from pathlib import Path
root = Path(__file__).resolve().parents[1]
helper = (root/'lib/core/database/database_helper.dart').read_text(encoding='utf-8')
provider = (root/'lib/features/table_management/presentation/providers/table_provider.dart').read_text(encoding='utf-8')
db = sqlite3.connect(':memory:')
db.executescript('''CREATE TABLE tables(id INTEGER PRIMARY KEY, name TEXT, branch_id TEXT,
 status TEXT, customer_name TEXT, zone TEXT, capacity INTEGER, is_active INTEGER);
 CREATE TABLE table_carts(table_id INTEGER, note TEXT);
 INSERT INTO tables VALUES(14,'Meja 1','branch-a','occupied','Guest','Dalam',4,1);
 INSERT INTO table_carts VALUES(14,'Unpaid meal');''')
migration = re.search(r"ALTER TABLE tables ADD COLUMN server_id INTEGER", helper).group()
db.execute(migration)
name_where = re.search(r"where: '([^']*server_id IS NULL[^']*)'", provider).group(1)
local_id = db.execute('SELECT id FROM tables WHERE '+name_where, ['branch-a','meja 1']).fetchone()[0]
assert local_id == 14
db.execute('UPDATE tables SET server_id=?,name=?,zone=?,capacity=? WHERE id=?', [74,'Teras A','Luar',6,local_id])
assert db.execute('SELECT id,status,customer_name FROM tables').fetchone() == (14,'occupied','Guest')
assert db.execute('SELECT table_id,note FROM table_carts').fetchone() == (14,'Unpaid meal')
assert db.execute('SELECT id FROM tables WHERE '+name_where, ['branch-b','Teras A']).fetchone() is None
print('PASS: SQLite v31 migration, branch/name lookup, rename retains local ID and unpaid cart')
