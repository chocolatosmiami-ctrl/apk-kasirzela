import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'pos_rumah_makan.db');
    return await openDatabase(
      path,
      version: 26,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async => await db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v21: SAFE migration - TIDAK PERNAH DROP shifts
    // Hanya ALTER TABLE untuk tambah kolom yang kurang
    if (oldVersion < 21) {
      try { await db.execute("ALTER TABLE shifts ADD COLUMN branch_id TEXT"); } catch (_) {}
      try { await db.execute("ALTER TABLE shifts ADD COLUMN status TEXT NOT NULL DEFAULT 'open'"); } catch (_) {}
      debugPrint('v21: shifts columns ensured (no drop)');
    }
    if (oldVersion < 26) {
      // SQLite tidak support ALTER COLUMN type, jadi recreate data
      // Buat kolom qty_new REAL, copy data, drop qty, rename
      try {
        await db.execute('ALTER TABLE order_items ADD COLUMN qty_real REAL DEFAULT 1');
        await db.execute('UPDATE order_items SET qty_real = CAST(qty AS REAL)');
        // Tidak bisa drop kolom di SQLite lama, tapi qty_real akan dipakai
      } catch (_) {}
      debugPrint('v26: order_items.qty_real column added');
    }

    if (oldVersion < 25) {
      try { await db.execute('ALTER TABLE order_items ADD COLUMN unit TEXT'); } catch (_) {}
      debugPrint('v25: order_items.unit column added');
    }

    if (oldVersion < 24) {
      try { await db.execute('ALTER TABLE orders ADD COLUMN cashier_name TEXT'); } catch (_) {}
      debugPrint('v24: orders.cashier_name column added');
    }

    if (oldVersion < 23) {
      // v23: Clear role_permissions cache agar pull ulang dari Supabase
      // Fix: shift permission sekarang dikontrol dari dashboard
      try { await db.execute('DELETE FROM role_permissions'); } catch (_) {}
      debugPrint('v23: role_permissions cache cleared - will re-sync from Supabase');
    }

    if (oldVersion < 22) {
      try { await db.execute('ALTER TABLE retail_products ADD COLUMN branch_id TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE retail_products ADD COLUMN created_by TEXT'); } catch (_) {}
      debugPrint('v22: retail_products columns ensured');
    }

    // v17: ensure branch_id ada di menu_items
    if (oldVersion < 17) {
      try { await db.execute('ALTER TABLE menu_items ADD COLUMN branch_id TEXT'); } catch (_) {}
      debugPrint('v17: menu_items.branch_id ensured');
    }

    // v16: ensure branch_id & synced di orders
    if (oldVersion < 16) {
      try { await db.execute('ALTER TABLE orders ADD COLUMN branch_id TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE orders ADD COLUMN synced INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE orders ADD COLUMN service_charge_amount REAL NOT NULL DEFAULT 0'); } catch (_) {}
      debugPrint('v16: orders columns ensured');
    }

    // v15: tambah kolom email di ingredients
    if (oldVersion < 15) {
      try {
        await db.execute("ALTER TABLE ingredients ADD COLUMN email TEXT");
        debugPrint('v15: ingredients.email added');
      } catch (e) {
        debugPrint('v15: \$e');
      }
    }
  }


  Future<void> _createTables(Database db, int version) async {
    // Users
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        auth_id TEXT,
        owner_id TEXT,
        branch_id TEXT,
        name TEXT NOT NULL,
        email TEXT,
        pin TEXT,
        pin_hash TEXT NOT NULL DEFAULT '',
        role TEXT NOT NULL DEFAULT 'kasir',
        is_active INTEGER NOT NULL DEFAULT 1,
        firebase_uid TEXT,
        created_at TEXT
      )
    ''');

    // Categories
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT '🍽️',
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Menu items
    await db.execute('''
      CREATE TABLE menu_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        branch_id TEXT,
        name TEXT NOT NULL,
        description TEXT,
        price REAL NOT NULL,
        image_path TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        has_stock INTEGER NOT NULL DEFAULT 0,
        stock INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories (id)
      )
    ''');

    // Orders
    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_number TEXT NOT NULL UNIQUE,
        table_number TEXT,
        order_type TEXT NOT NULL DEFAULT 'dine_in',
        status TEXT NOT NULL DEFAULT 'new',
        subtotal REAL NOT NULL DEFAULT 0,
        discount_type TEXT DEFAULT 'none',
        discount_value REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        tax_percent REAL NOT NULL DEFAULT 0,
        tax_amount REAL NOT NULL DEFAULT 0,
        service_charge_amount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        payment_method TEXT,
        paid_amount REAL NOT NULL DEFAULT 0,
        change_amount REAL NOT NULL DEFAULT 0,
        cashier_id TEXT,
        cashier_name TEXT,
        note TEXT,
        cancel_reason TEXT,
        branch_id TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Order items
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        menu_item_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        qty REAL NOT NULL DEFAULT 1,
        unit TEXT,
        note TEXT,
        subtotal REAL NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');

    // Shifts
    await db.execute('''
      CREATE TABLE shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        user_name TEXT NOT NULL,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        opening_cash REAL NOT NULL DEFAULT 0,
        closing_cash REAL NOT NULL DEFAULT 0,
        total_sales REAL NOT NULL DEFAULT 0,
        total_cash REAL NOT NULL DEFAULT 0,
        total_non_cash REAL NOT NULL DEFAULT 0,
        total_expenses REAL NOT NULL DEFAULT 0,
        expected_cash REAL NOT NULL DEFAULT 0,
        cash_difference REAL NOT NULL DEFAULT 0,
        total_transactions INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'open'
      )
    ''');

    // Custom presets (hak akses yang bisa dikustomisasi admin)
    await db.execute('''
      CREATE TABLE presets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL DEFAULT '📋',
        color INTEGER NOT NULL DEFAULT 0xFF1565C0,
        permissions TEXT NOT NULL DEFAULT '',
        is_default INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Branches (multi cabang)
    await db.execute('''
      CREATE TABLE branches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        address TEXT,
        phone TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_current INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Settings
    await db.execute('''
      CREATE TABLE settings (
        key TEXT NOT NULL,
        value TEXT,
        email TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (key, email)
      )
    ''');

    // Ingredients (bahan makanan)
    await db.execute('''
      CREATE TABLE ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT 'pcs',
        current_stock REAL NOT NULL DEFAULT 0,
        min_stock REAL NOT NULL DEFAULT 1,
        branch_id TEXT,
        email TEXT,
        notes TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    // Menu-Ingredient links
    await db.execute('''
      CREATE TABLE menu_ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_item_id INTEGER NOT NULL,
        ingredient_id INTEGER NOT NULL,
        quantity_used REAL NOT NULL DEFAULT 1,
        FOREIGN KEY (menu_item_id) REFERENCES menu_items (id) ON DELETE CASCADE,
        FOREIGN KEY (ingredient_id) REFERENCES ingredients (id) ON DELETE CASCADE
      )
    ''');

    // Expenses (pengeluaran harian)
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        cashier_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Role permissions
    await db.execute('''
      CREATE TABLE role_permissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        permission TEXT NOT NULL,
        is_allowed INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // ── Table management ─────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tables (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        zone TEXT NOT NULL DEFAULT 'Dalam',
        capacity INTEGER NOT NULL DEFAULT 4,
        status TEXT NOT NULL DEFAULT 'empty',
        active_order_id INTEGER,
        customer_name TEXT,
        reserved_at TEXT,
        occupied_at TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // ── Retail tables ─────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS retail_products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sku TEXT NOT NULL,
        barcode TEXT,
        category TEXT NOT NULL DEFAULT 'Umum',
        sell_price REAL NOT NULL DEFAULT 0,
        hpp REAL NOT NULL DEFAULT 0,
        stock REAL NOT NULL DEFAULT 0,
        min_stock REAL NOT NULL DEFAULT 5,
        unit TEXT NOT NULL DEFAULT 'pcs',
        is_by_weight INTEGER NOT NULL DEFAULT 0,
        image_path TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        branch_id TEXT,
        created_by TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        unit_name TEXT NOT NULL,
        conversion REAL NOT NULL DEFAULT 1,
        sell_price REAL NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        type TEXT NOT NULL,
        qty REAL NOT NULL,
        stock_before REAL NOT NULL DEFAULT 0,
        stock_after REAL NOT NULL DEFAULT 0,
        note TEXT,
        created_at TEXT,
        created_by TEXT
      )
    ''');

    // Performance indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_status_created ON orders(status, created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_menu_items_category ON menu_items(category_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_users_auth_id ON users(auth_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_shifts_user_id ON shifts(user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_created_at ON expenses(created_at)');

    // Offline transaction audit log (second source of truth untuk grace period)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_trx_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recorded_at TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 150,
        cumulative_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _insertDefaultData(db);
    await _insertDefaultPermissions(db);
  }

  Future<void> _insertDefaultPermissions(Database db) async {
    // Admin permissions - all allowed
    final adminPerms = [
      'kasir', 'pesanan', 'menu', 'laporan', 'pengaturan',
      'pengeluaran', 'void_transaksi', 'hapus_menu', 'manajemen_user',
      'lihat_laporan', 'export_pdf',
    ];
    for (final perm in adminPerms) {
      await db.insert('role_permissions', {
        'role': 'admin', 'permission': perm, 'is_allowed': 1
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Manajer permissions
    final manajerPerms = [
      'kasir', 'pesanan', 'menu', 'laporan', 'pengeluaran',
      'lihat_laporan', 'export_pdf', 'void_transaksi',
    ];
    for (final perm in manajerPerms) {
      await db.insert('role_permissions', {
        'role': 'manajer', 'permission': perm, 'is_allowed': 1
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Kasir permissions - limited
    final kasirPerms = ['kasir', 'pesanan', 'pengeluaran'];
    for (final perm in kasirPerms) {
      await db.insert('role_permissions', {
        'role': 'kasir', 'permission': perm, 'is_allowed': 1
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _insertDefaultData(Database db) async {
    final now = DateTime.now().toIso8601String();

    // BUG 2 FIX: Default users pakai PIN random (bukan 1234/0000/5678).
    // PIN di-generate sekali saat install pertama dan WAJIB diganti.
    // Dicetak di log debug agar admin tahu PIN awal.
    final rand = Random.secure();
    String _randPin() => (1000 + rand.nextInt(8999)).toString(); // 4 digit, bukan 0000-0999

    final adminPin   = _randPin();
    final manajerPin = _randPin();
    final kasirPin   = _randPin();

    debugPrint('🔑 [SETUP] Default PINs (GANTI SEGERA SETELAH LOGIN PERTAMA):');
    debugPrint('🔑   Admin  : $adminPin');
    debugPrint('🔑   Manajer: $manajerPin');
    debugPrint('🔑   Kasir 1: $kasirPin');

    // Default users — salt pakai 'default_<role>' karena belum ada userId
    await db.insert('users', {
      'name': 'Admin', 'pin_hash': _hashPin(adminPin, userId: 'default_admin'),
      'role': 'admin', 'is_active': 1, 'created_at': now,
    });
    await db.insert('users', {
      'name': 'Manajer', 'pin_hash': _hashPin(manajerPin, userId: 'default_manajer'),
      'role': 'manajer', 'is_active': 1, 'created_at': now,
    });
    await db.insert('users', {
      'name': 'KASIR ZL 1', 'pin_hash': _hashPin(kasirPin, userId: 'default_kasir'),
      'role': 'kasir', 'is_active': 1, 'created_at': now,
    });

    // Categories
    final categories = [
      {'name': 'Makanan Berat', 'icon': '🍛', 'sort_order': 1},
      {'name': 'Snack', 'icon': '🍟', 'sort_order': 2},
      {'name': 'Minuman', 'icon': '🥤', 'sort_order': 3},
      {'name': 'Paket Hemat', 'icon': '🎁', 'sort_order': 4},
      {'name': 'Dessert', 'icon': '🍰', 'sort_order': 5},
    ];
    for (final cat in categories) {
      await db.insert('categories', {...cat, 'is_active': 1});
    }

    // Menu items
    final menus = [
      {'category_id': 1, 'name': 'Nasi Goreng Spesial', 'description': 'Nasi goreng dengan telur & ayam', 'price': 22000.0},
      {'category_id': 1, 'name': 'Nasi Ayam Bakar', 'description': 'Ayam bakar bumbu kecap', 'price': 28000.0},
      {'category_id': 1, 'name': 'Mie Goreng Jumbo', 'description': 'Mie goreng porsi besar', 'price': 20000.0},
      {'category_id': 1, 'name': 'Nasi Rendang', 'description': 'Rendang daging sapi Minang', 'price': 35000.0},
      {'category_id': 1, 'name': 'Soto Ayam', 'description': 'Soto kuah bening', 'price': 18000.0},
      {'category_id': 2, 'name': 'Kentang Goreng', 'description': 'Crispy dengan saus sambal', 'price': 12000.0},
      {'category_id': 2, 'name': 'Pisang Goreng', 'description': 'Pisang kepok goreng', 'price': 10000.0},
      {'category_id': 2, 'name': 'Tempe Mendoan', 'description': 'Tempe tipis gurih', 'price': 8000.0},
      {'category_id': 3, 'name': 'Es Teh Manis', 'description': 'Teh manis segar', 'price': 5000.0},
      {'category_id': 3, 'name': 'Es Jeruk', 'description': 'Jeruk segar diperas', 'price': 8000.0},
      {'category_id': 3, 'name': 'Jus Alpukat', 'description': 'Jus alpukat dengan susu', 'price': 15000.0},
      {'category_id': 3, 'name': 'Kopi Hitam', 'description': 'Kopi robusta pilihan', 'price': 7000.0},
      {'category_id': 3, 'name': 'Air Mineral', 'description': 'Air mineral 600ml', 'price': 5000.0},
      {'category_id': 4, 'name': 'Paket Nasi Goreng', 'description': 'Nasi goreng + Es teh', 'price': 25000.0},
      {'category_id': 4, 'name': 'Paket Ayam Bakar', 'description': 'Nasi ayam bakar + Es jeruk', 'price': 32000.0},
      {'category_id': 5, 'name': 'Es Cendol', 'description': 'Cendol santan gula merah', 'price': 12000.0},
      {'category_id': 5, 'name': 'Bubur Kacang Hijau', 'description': 'Kacang hijau santan hangat', 'price': 10000.0},
      {'category_id': 5, 'name': 'Puding Coklat', 'description': 'Puding lembut saus vanilla', 'price': 8000.0},
    ];
    for (final item in menus) {
      await db.insert('menu_items', {
        ...item, 'is_active': 1, 'has_stock': 0, 'stock': 0, 'created_at': now,
      });
    }

    // Default presets
    final presets = [
      {'name': 'Minimal', 'emoji': '🔒', 'color': 0xFFD32F2F, 'permissions': 'kasir,shift', 'is_default': 1, 'sort_order': 1},
      {'name': 'Standar', 'emoji': '📋', 'color': 0xFF1565C0, 'permissions': 'kasir,shift,pesanan,pengeluaran', 'is_default': 1, 'sort_order': 2},
      {'name': 'Lengkap', 'emoji': '🔓', 'color': 0xFF2E7D32, 'permissions': 'kasir,shift,diskon,pesanan,update_pesanan,menu,tambah_menu,pengeluaran,laporan,export_pdf,inventory,pengaturan', 'is_default': 1, 'sort_order': 3},
    ];
    for (final p in presets) {
      await db.insert('presets', p);
    }

    // Default branch
    await db.insert('branches', {
      'name': 'Cabang Utama',
      'address': 'Jl. Raya No. 123',
      'phone': '08123456789',
      'is_active': 1,
      'is_current': 1,
      'created_at': now,
    });

    // Settings
    final settings = {
      'store_name': 'Warung Makan Barokah',
      'store_address': 'Jl. Raya No. 123',
      'store_phone': '08123456789',
      'receipt_header': 'Terima kasih telah berkunjung',
      'receipt_footer': 'Selamat menikmati!',
      'tax_enabled': '0', 'tax_percent': '11',
      'dark_mode': '0', 'receipt_width': '58',
      'currency_symbol': 'Rp',
      'branch_id': '1',
      'branch_name': 'Cabang Utama',
      'print_kitchen': '1', // cetak nota dapur
      'print_customer': '1', // cetak nota customer
    };
    for (final e in settings.entries) {
      await db.insert('settings', {'key': e.key, 'value': e.value});
    }
  }

  // hashPin: SHA-256 tanpa salt tambahan.
  // Catatan: salt per-user bisa ditambahkan di masa depan saat ada migrasi DB,
  // tapi sekarang semua user existing pakai hash tanpa salt — jangan ubah ini.
  String _hashPin(String pin, {String userId = ''}) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  static String hashPin(String pin, {String userId = ''}) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  // Legacy alias — sama dengan hashPin, untuk kompatibilitas
  static String hashPinLegacy(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  // CRUD helpers
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> update(String table, Map<String, dynamic> data, String where, List<dynamic> whereArgs) async {
    final db = await database;
    return await db.update(table, data, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table, String where, List<dynamic> whereArgs) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<List<Map<String, dynamic>>> query(String table, {
    String? where, List<dynamic>? whereArgs, String? orderBy, int? limit,
  }) async {
    final db = await database;
    return await db.query(table, where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit);
  }

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? args]) async {
    final db = await database;
    return await db.rawQuery(sql, args);
  }

  Future<int> rawInsert(String sql, [List<dynamic>? args]) async {
    final db = await database;
    return await db.rawInsert(sql, args);
  }

  Future<int> rawUpdate(String sql, [List<dynamic>? args]) async {
    final db = await database;
    return await db.rawUpdate(sql, args);
  }

  /// Jalankan beberapa operasi dalam satu SQLite transaction.
  /// Jika ada error di tengah, semua operasi di-rollback otomatis.
  Future<T> runTransaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return await db.transaction(action);
  }

  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'pos_rumah_makan.db');
  }

  // Get permissions for a role
  Future<List<String>> getRolePermissions(String role) async {
    // Owner = same permissions as admin
    final effectiveRole = role == 'owner' ? 'admin' : role;
    final results = await query(
      'role_permissions',
      where: 'role = ? AND is_allowed = 1',
      whereArgs: [effectiveRole],
    );
    if (results.isNotEmpty) {
      return results.map((r) => r['permission'] as String).toList();
    }
    // Default fallback permissions by role
    switch (effectiveRole) {
      case 'admin':
        return ['kasir','shift','pesanan','menu','pengeluaran',
          'inventory','laporan','manajemen_user','hak_akses'];
      case 'manajer':
        return ['kasir','menu','pengeluaran'];
      default: // kasir
        return ['kasir'];
    }
  }

  // Update permission ke SQLite lokal saja (tanpa Supabase)
  Future<void> setPermissionLocalOnly(String role, String permission, bool allowed) async {
    final existing = await query(
      'role_permissions',
      where: 'role = ? AND permission = ?',
      whereArgs: [role, permission],
    );
    if (existing.isNotEmpty) {
      await update('role_permissions', {'is_allowed': allowed ? 1 : 0},
          'role = ? AND permission = ?', [role, permission]);
    } else {
      await insert('role_permissions', {
        'role': role, 'permission': permission, 'is_allowed': allowed ? 1 : 0,
      });
    }
  }

  // Update permission — simpan lokal
  // Untuk sync ke Supabase, panggil PermissionSyncService.pushPermission() setelahnya
  Future<void> setPermission(String role, String permission, bool allowed) async {
    await setPermissionLocalOnly(role, permission, allowed);
  }
}