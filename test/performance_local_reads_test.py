"""SQLite equivalence and query-plan tests; never connects to Supabase."""
from pathlib import Path
import re
import sqlite3

root = Path(__file__).resolve().parents[1]
db = sqlite3.connect(':memory:')
db.executescript('''
CREATE TABLE orders(id INTEGER PRIMARY KEY, status TEXT, cashier_id TEXT, created_at TEXT, total INTEGER);
CREATE TABLE order_items(id INTEGER PRIMARY KEY, order_id INTEGER REFERENCES orders(id), name TEXT, qty INTEGER, subtotal INTEGER);
CREATE TABLE menu_items(id INTEGER PRIMARY KEY, branch_id TEXT, name TEXT, price INTEGER, image_path TEXT, stock INTEGER, sort_order INTEGER);
CREATE TABLE retail_products(id INTEGER PRIMARY KEY, branch_id TEXT, sku TEXT, stock INTEGER);
''')
with db:
    for order in range(1, 501):
        db.execute("INSERT INTO orders VALUES(?, 'paid', 'account-a', '2026-11-03T12:00:00', 29000)", (order,))
        db.executemany('INSERT INTO order_items(order_id,name,qty,subtotal) VALUES(?,?,?,?)',
                       [(order, 'Nasi', 1, 28000), (order, 'Service', 1, 1000)])
    db.executemany('INSERT INTO menu_items VALUES(?,?,?,?,?,?,?)',
                   [(i, 'one', f'Menu {i}', i*1000, f'local-image-{i}', 9, i) for i in range(1, 151)])
    db.execute("INSERT INTO retail_products VALUES(1,'one','sku-a',8)")

def snapshot():
    return {name: db.execute(f'SELECT * FROM {name} ORDER BY id').fetchall()
            for name in ['orders', 'order_items', 'menu_items', 'retail_products']}

before = snapshot()
index_sql = re.findall(r"'(CREATE INDEX[^']+)'", (root/'lib/core/database/local_read_indexes.dart').read_text())
assert len(index_sql) == 5
for repeat in range(2):
    for sql in index_sql:
        db.execute(sql)
assert snapshot() == before, 'indexes must not modify business rows, receipt IDs or totals'
plan = str(db.execute('EXPLAIN QUERY PLAN SELECT * FROM order_items WHERE order_id IN (?,?)', [1, 2]).fetchall())
assert 'pos_order_items_order' in plan and 'SEARCH' in plan, plan

trace = []
db.set_trace_callback(trace.append)
legacy = {i: db.execute('SELECT * FROM order_items WHERE order_id = ?', [i]).fetchall() for i in range(1, 501)}
legacy_queries = len(trace)
trace.clear()
batched = {}
for start in range(1, 501, 400):
    ids = list(range(start, min(start+400, 501)))
    rows = db.execute(f"SELECT * FROM order_items WHERE order_id IN ({','.join('?' for _ in ids)}) ORDER BY order_id,id", ids).fetchall()
    for row in rows:
        batched.setdefault(row[1], []).append(row)
batch_queries = len(trace)
db.set_trace_callback(None)
assert legacy == batched
assert legacy_queries == 500 and batch_queries == 2
assert all(sum(r[4] for r in items) == 29000 for items in batched.values())
print('PASS: history 500 -> 2 item SELECTs; all 1,000 items/amounts/IDs identical')
print('PASS: five non-unique indexes repeatable, indexed lookup used, business rows unchanged')

# Compare old per-row menu cache operations with the equivalent bulk transaction.
# Existing IDs, local sort order, images and stock must survive metadata refresh.
def make_menu_db():
    copy = sqlite3.connect(':memory:')
    db.backup(copy)
    copy.execute('PRAGMA foreign_keys = ON')
    copy.execute('CREATE TABLE recipe(menu_id INTEGER REFERENCES menu_items(id), ingredient TEXT)')
    copy.execute("INSERT INTO recipe VALUES(1,'ayam')")
    copy.commit()
    return copy

old, new = make_menu_db(), make_menu_db()
remote = [{'name': f'Menu {i}', 'price': i*1500, 'image': '' if i % 2 else f'remote-{i}'} for i in range(1, 154)]
remote += [remote[-1].copy()]  # duplicate input must still update the same local ID

def update_menu(conn, batched):
    local_sort = dict(conn.execute('SELECT name,sort_order FROM menu_items WHERE branch_id=?', ['one']))
    names = set(local_sort)
    if batched:
        conn.execute('BEGIN')
    for i, row in enumerate(remote):
        if not batched:
            exists = conn.execute('SELECT id FROM menu_items WHERE branch_id=? AND name=?', ['one', row['name']]).fetchall()
            conn.execute('BEGIN')
        else:
            exists = row['name'] in names
        sort = local_sort.get(row['name'], i)
        if exists:
            conn.execute('UPDATE menu_items SET price=?,sort_order=? WHERE branch_id=? AND name=?', [row['price'], sort, 'one', row['name']])
            if row['image']:
                conn.execute('UPDATE menu_items SET image_path=? WHERE branch_id=? AND name=?', [row['image'], 'one', row['name']])
        else:
            conn.execute('INSERT INTO menu_items(branch_id,name,price,image_path,stock,sort_order) VALUES(?,?,?,?,?,?)', ['one', row['name'], row['price'], row['image'] or None, 0, sort])
            names.add(row['name'])
        if not batched:
            conn.commit()
    if batched:
        conn.commit()

update_menu(old, False)
update_menu(new, True)
assert old.execute('SELECT * FROM menu_items ORDER BY id').fetchall() == new.execute('SELECT * FROM menu_items ORDER BY id').fetchall()
assert new.execute('SELECT * FROM recipe').fetchall() == [(1, 'ayam')]
assert new.execute('SELECT id,image_path,stock,sort_order FROM menu_items WHERE id=1').fetchone() == (1,'local-image-1',9,1)
print('PASS: batched menu cache preserves prior behavior, receipt-linked IDs, recipe links, local images/stock/order')

def retail_db():
    result = sqlite3.connect(':memory:')
    result.execute('CREATE TABLE products(id INTEGER PRIMARY KEY, branch_id TEXT, sku TEXT, name TEXT, stock REAL, price REAL, hpp REAL)')
    result.executemany('INSERT INTO products VALUES(?,?,?,?,?,?,?)',
                       [(1,'a','sku-a','A',4,28000,10000), (2,'a',None,'Legacy',8,2000,1000),
                        (3,'a','','Empty SKU',2,3000,1000), (4,'b','sku-a','Other branch',20,50000,10000)])
    result.commit()
    return result

old_retail, new_retail = retail_db(), retail_db()
retail_input = [('sku-a','A',9,29000,11000), (None,'Legacy update',3,2000,1000), (None,'Another legacy product',4,4000,1000),
                ('new','New product',5,7000,3000), ('new','New product',6,7000,3000)]

def refresh_retail(conn, batch):
    lookup = {}
    if batch:
        lookup = {sku: row_id for row_id,sku in conn.execute('SELECT id,sku FROM products WHERE branch_id=? ORDER BY id DESC', ['a']) if sku is not None}
        conn.execute('BEGIN')
    for sku,name,stock,price,hpp in retail_input:
        if not batch:
            row = conn.execute('SELECT id FROM products WHERE sku=? AND branch_id=?', [sku or '', 'a']).fetchone()
            row_id = row[0] if row else None
            conn.execute('BEGIN')
        else:
            row_id = lookup.get(sku or '')
        if row_id is None:
            inserted = conn.execute('INSERT INTO products(branch_id,sku,name,stock,price,hpp) VALUES(?,?,?,?,?,?)', ['a',sku,name,stock,price,hpp]).lastrowid
            if sku is not None:
                lookup[sku] = inserted
        else:
            conn.execute('UPDATE products SET sku=?,name=?,stock=?,price=?,hpp=? WHERE id=?', [sku,name,stock,price,hpp,row_id])
            if sku is None:
                lookup.pop('', None)
        if not batch:
            conn.commit()
    if batch:
        conn.commit()

refresh_retail(old_retail, False)
refresh_retail(new_retail, True)
assert old_retail.execute('SELECT * FROM products ORDER BY id').fetchall() == new_retail.execute('SELECT * FROM products ORDER BY id').fetchall()
print('PASS: retail batch preserves IDs, price/HPP/stock, branch separation and legacy NULL-SKU behavior')
