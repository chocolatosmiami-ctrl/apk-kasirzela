/// Non-unique SQLite indexes only: no row deletion, renumbering or remote SQL.
const localReadIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS pos_order_items_order ON order_items(order_id)',
  'CREATE INDEX IF NOT EXISTS pos_orders_status_date ON orders(status, created_at)',
  'CREATE INDEX IF NOT EXISTS pos_orders_cashier_date ON orders(cashier_id, created_at)',
  'CREATE INDEX IF NOT EXISTS pos_menu_branch_name ON menu_items(branch_id, name)',
  'CREATE INDEX IF NOT EXISTS pos_retail_branch_sku ON retail_products(branch_id, sku)',
];
