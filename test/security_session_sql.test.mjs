// Run only in the complete isolated test sandbox. Node >=22.13, no new packages.
// Executes actual Dart-source SQL predicates against a real in-memory SQLite DB;
// this is not a substitute for Flutter navigation/transaction integration tests.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

const source = path => readFileSync(new URL('../lib/' + path, import.meta.url), 'utf8');
const retail = source('features/retail/presentation/providers/retail_provider.dart');
const food = source('features/cashier/presentation/providers/cashier_provider.dart');
const shift = source('features/shift/presentation/providers/shift_provider.dart');
function captured(text, pattern) {
  const match = text.match(pattern);
  assert.ok(match, 'actual application SQL statement must be locatable');
  return match[1];
}
function fixture() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    CREATE TABLE retail_products(id INTEGER PRIMARY KEY, branch_id TEXT,
      created_by TEXT, is_active INTEGER, stock REAL);
    INSERT INTO retail_products VALUES(1,'branch-a','user-u',1,10),
      (2,'branch-b','other-user',1,10),(3,NULL,NULL,1,10);
    CREATE TABLE menu_items(id INTEGER PRIMARY KEY, branch_id TEXT, stock REAL);
    INSERT INTO menu_items VALUES(1,'branch-a',10),(2,'branch-b',10),(3,NULL,10);
    CREATE TABLE shifts(id INTEGER PRIMARY KEY,user_id TEXT,status TEXT);
    INSERT INTO shifts VALUES(1,'user-a','open'),(2,'user-b','open');
  `);
  return db;
}

test('retail read cannot turn creator identity or unknown provenance into branch access', () => {
  const db = fixture();
  try {
    const localRead = retail.slice(retail.indexOf('// Baca dari SQLite'));
    const where = captured(localRead, /where:\s*'([^']+)'/);
    const args = (where.match(/\?/g) ?? []).length === 1 ? ['branch-b'] : ['user-u','branch-b'];
    const rows = db.prepare(`SELECT id FROM retail_products WHERE ${where} ORDER BY id`).all(...args);
    assert.deepEqual(rows.map(row => row.id), [2]);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM retail_products').get().n, 3,
      'unassigned legacy data is retained, not deleted or reattributed');
  } finally { db.close(); }
});

test('food stock sink refuses a foreign branch but preserves intentional global menus', () => {
  const db = fixture();
  try {
    const where = captured(food, /await txn\.update\(\s*'menu_items',[\s\S]*?where:\s*'([^']+)'/);
    const update = db.prepare(`UPDATE menu_items SET stock = ? WHERE ${where}`);
    const args = (id) => (where.match(/\?/g) ?? []).length === 2 ? [8,id,'branch-b'] : [8,id];
    assert.equal(update.run(...args(1)).changes, 0);
    assert.equal(db.prepare('SELECT stock FROM menu_items WHERE id=1').get().stock, 10);
    assert.equal(update.run(...args(2)).changes, 1);
    assert.equal(update.run(...args(3)).changes, 1);
  } finally { db.close(); }
});

test('retail stock sink refuses another branch even when its integer ID is known', () => {
  const db = fixture();
  try {
    const where = captured(retail, /UPDATE retail_products SET stock = \? WHERE ([^']+)'/);
    const update = db.prepare(`UPDATE retail_products SET stock = ? WHERE ${where}`);
    const args = id => (where.match(/\?/g) ?? []).length === 2 ? [8,id,'branch-b'] : [8,id];
    assert.equal(update.run(...args(1)).changes, 0);
    assert.equal(db.prepare('SELECT stock FROM retail_products WHERE id=1').get().stock, 10);
    assert.equal(update.run(...args(2)).changes, 1);
  } finally { db.close(); }
});

test('shift close predicate refuses a known shift ID owned by another principal', () => {
  const db = fixture();
  try {
    const where = captured(shift, /update\(\s*'shifts',\s*updated\.toMap\(\),\s*'([^']+)'/);
    const update = db.prepare(`UPDATE shifts SET status = ? WHERE ${where}`);
    const args = id => (where.match(/\?/g) ?? []).length === 2 ? ['closed',id,'user-b'] : ['closed',id];
    assert.equal(update.run(...args(1)).changes, 0);
    assert.equal(db.prepare('SELECT status FROM shifts WHERE id=1').get().status, 'open');
    assert.equal(update.run(...args(2)).changes, 1);
  } finally { db.close(); }
});
