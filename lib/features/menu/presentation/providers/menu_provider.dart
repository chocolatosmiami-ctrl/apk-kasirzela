import '../../../../core/utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/menu_models.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/config/supabase_config.dart';

class MenuProvider extends ChangeNotifier {
  List<CategoryModel> _categories = [];
  List<MenuItemModel> _menuItems = [];
  bool _isLoading = false;
  int? _selectedCategoryId;

  // ── Stock-tracking state (diset oleh syncStockToday) ──────
  /// true setelah syncStockToday pertama kali selesai (berhasil atau gagal)
  bool _stockLoadDone = false;
  bool get stockLoadDone => _stockLoadDone;

  /// true jika hari ini minimal 1 menu punya data stok (has_stock = 1)
  bool get anyStockConfiguredToday =>
      _menuItems.any((m) => m.hasStock);

  List<CategoryModel> get categories => _categories;
  List<MenuItemModel> get menuItems => _menuItems;
  bool get isLoading => _isLoading;
  int? get selectedCategoryId => _selectedCategoryId;

  List<MenuItemModel> get filteredMenuItems {
    if (_selectedCategoryId == null) return _menuItems;
    return _menuItems.where((item) => item.categoryId == _selectedCategoryId).toList();
  }

  List<MenuItemModel> get activeMenuItems => _menuItems.where((item) => item.isActive).toList();

  // ── Stock helper methods (dipakai oleh _MenuCard di cashier_screen) ──

  /// true jika menu ini diblokir karena stok habis hari ini
  /// (has_stock = 1 AND stock = 0)
  bool isMenuBlocked(int menuItemId) {
    final item = _menuItems.where((m) => m.id == menuItemId).firstOrNull;
    if (item == null) return false;
    return item.hasStock && item.stock <= 0;
  }

  /// Kembalikan stok sisa hari ini, atau null jika menu tidak dikontrol stok
  double? getEffectiveStockSisa(int menuItemId) {
    final item = _menuItems.where((m) => m.id == menuItemId).firstOrNull;
    if (item == null || !item.hasStock) return null;
    return item.stock.toDouble();
  }

  /// true jika menu ini sudah di-set stok hari ini (has_stock = 1)
  bool isMenuStockConfigured(int menuItemId) {
    final item = _menuItems.where((m) => m.id == menuItemId).firstOrNull;
    if (item == null) return false;
    return item.hasStock;
  }

  Future<void> loadData() async {
    debugPrint('📊 [MENU] <void> loadData called — isReordering=$_isReordering');
    if (_isReordering) {
      debugPrint('📊 [MENU] loadData BLOCKED — sedang reorder');
      return;
    }
    // Jangan load ulang jika baru selesai reorder dalam 15 detik
    if (_lastReorderTime != null &&
        DateTime.now().difference(_lastReorderTime!).inSeconds < 15) {
      debugPrint('📊 [MENU] loadData BLOCKED — baru reorder');
      return;
    }
    _isLoading = true;
    notifyListeners();

    await loadCategories();
    await loadMenuItems();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadCategories() async {
    debugPrint('📊 [MENU] <void> loadCategories called');
    final results = await DatabaseHelper.instance.query(
      'categories',
      orderBy: 'sort_order ASC',
    );
    _categories = results.map((e) => CategoryModel.fromMap(e)).toList();
    notifyListeners();
  }

  Future<void> loadMenuItems() async {
    debugPrint('📊 [MENU] loadMenuItems called — isReordering=$_isReordering lastReorder=$_lastReorderTime');
    // Jangan load ulang saat sedang reorder
    if (_isReordering) {
      debugPrint('📊 [MENU] loadMenuItems BLOCKED — sedang reorder');
      return;
    }
    // Jangan load ulang jika baru selesai reorder dalam 15 detik
    if (_lastReorderTime != null &&
        DateTime.now().difference(_lastReorderTime!).inSeconds < 15) {
      debugPrint('📊 [MENU] loadMenuItems BLOCKED — baru reorder ${DateTime.now().difference(_lastReorderTime!).inSeconds}s ago');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      debugPrint('📊 [MENU] branchId=$branchId');

      // Load dari SQLite (filter by branch_id atau global/null)
      List<Map<String,dynamic>> results;
      if (branchId.isNotEmpty) {
        results = await DatabaseHelper.instance.rawQuery('''
          SELECT m.*, c.name as category_name, c.icon as category_icon
          FROM menu_items m
          LEFT JOIN categories c ON m.category_id = c.id
          WHERE m.branch_id = ? OR m.branch_id IS NULL
          ORDER BY c.sort_order ASC, m.sort_order ASC, m.name ASC
        ''', [branchId]);
      } else {
        results = await DatabaseHelper.instance.rawQuery('''
          SELECT m.*, c.name as category_name, c.icon as category_icon
          FROM menu_items m
          LEFT JOIN categories c ON m.category_id = c.id
          ORDER BY c.sort_order ASC, m.sort_order ASC, m.name ASC
        ''');
      }

      _menuItems = results.map((e) => MenuItemModel.fromMap(e)).toList();
      debugPrint('📊 [MENU] SQLite: ${_menuItems.length} items (branchId=$branchId)');
      notifyListeners(); // Tampilkan data SQLite dulu (cepat)

      // Selalu sync dari Supabase di background untuk dapat update terbaru
      // (menu baru, edit harga, hapus menu dari owner)
      if (branchId.isNotEmpty) {
        _syncFromSupabase(branchId); // tidak await agar tidak block UI
      }
    } catch (e) {
      debugPrint('📊 [MENU] loadMenuItems error: $e - trying without branch filter');
      // Fallback: load without branch_id filter (before migration runs)
      try {
        final fallback = await DatabaseHelper.instance.rawQuery('''
          SELECT m.*, c.name as category_name, c.icon as category_icon
          FROM menu_items m
          LEFT JOIN categories c ON m.category_id = c.id
          ORDER BY c.sort_order ASC, m.sort_order ASC, m.name ASC
        ''');
        _menuItems = fallback.map((e) => MenuItemModel.fromMap(e)).toList();
        debugPrint('📊 [MENU] Fallback loaded: ${_menuItems.length} items');
      } catch (e2) {
        debugPrint('📊 [MENU] Fallback also failed: $e2');
      }
    }
    notifyListeners();
  }

  // Flag untuk mencegah sync timpa urutan yang baru di-reorder
  bool _isReordering = false;
  DateTime? _lastReorderTime;

  // Sync menu dari Supabase ke SQLite lokal
  Future<void> _syncFromSupabase(String branchId) async {
    // Jangan sync kalau sedang/baru reorder — bisa timpa urutan baru
    if (_isReordering) {
      debugPrint('📊 [MENU] Sync blocked — sedang reorder');
      return;
    }
    // Juga block kalau baru saja reorder (dalam 10 detik terakhir)
    if (_lastReorderTime != null &&
        DateTime.now().difference(_lastReorderTime!).inSeconds < 10) {
      debugPrint('📊 [MENU] Sync blocked — baru reorder ${DateTime.now().difference(_lastReorderTime!).inSeconds}s ago');
      return;
    }
    try {
      debugPrint('📊 [MENU] Syncing menu from Supabase...');

      // Ambil semua menu dari Supabase, order by sort_order
      final items = await SupabaseConfig.client
          .from('menu_items')
          .select('*')
          .eq('branch_id', branchId)
          .order('sort_order', ascending: true);

      debugPrint('📊 [SYNC⬇] START — branchId=$branchId');
      if (items.isEmpty) {
        debugPrint('📊 [SYNC⬇] Supabase kosong, skip hapus menu lokal');
        return;
      }
      if (items.length < 3) {
        debugPrint('📊 [SYNC⬇] Supabase hanya ${items.length} item, skip untuk keamanan');
        return;
      }

      final cats = await DatabaseHelper.instance.query('categories');
      int defaultCatId = cats.isNotEmpty ? cats.first['id'] as int : 1;

      // Ambil nama menu yang ada di Supabase
      final supabaseNames = items.map((i) => i['name']?.toString() ?? '').toSet();

      // Simpan sort_order lokal sebelum update
      final localOrders = <String, int>{};
      final existing = await DatabaseHelper.instance.rawQuery(
          'SELECT name, sort_order FROM menu_items WHERE branch_id = ?', [branchId]);
      for (final r in existing) {
        localOrders[r['name']?.toString() ?? ''] = (r['sort_order'] as int? ?? 999);
      }

      // FIX: Hapus HANYA menu yang ada di Supabase (bukan semua menu lokal)
      // Menu lokal yang baru ditambah tapi belum di-upload → TIDAK dihapus
      if (supabaseNames.isNotEmpty) {
        final placeholders = supabaseNames.map((_) => '?').join(',');
        await DatabaseHelper.instance.rawUpdate(
            'DELETE FROM menu_items WHERE branch_id = ? AND name IN ($placeholders)',
            [branchId, ...supabaseNames]);
      }

      // Insert dengan sort_order dari lokal (jika ada), fallback ke Supabase
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final isActive = (item['is_available'] as bool? ?? true) ? 1 : 0;
        final name = item['name']?.toString() ?? '';
        // Prioritas: sort_order lokal → sort_order Supabase → index
        final sortOrder = localOrders.containsKey(name)
            ? localOrders[name]!
            : (item['sort_order'] as num?)?.toInt() ?? i;
        try {
          await DatabaseHelper.instance.rawInsert(
              'INSERT OR REPLACE INTO menu_items '
                  '(category_id, branch_id, name, description, price, '
                  'is_active, has_stock, stock, sort_order, created_at) '
                  'VALUES (?,?,?,?,?,?,?,?,?,?)',
              [
                defaultCatId, branchId,
                item['name'], item['description'] ?? '',
                (item['price'] as num?)?.toDouble() ?? 0,
                isActive, 0, 0, sortOrder,
                item['created_at'] ?? DateTime.now().toIso8601String(),
              ]
          );
        } catch (e) {
          debugPrint('📊 [MENU] insert error: $e');
        }
      }

      // Reload dengan sort_order yang benar
      final results = await DatabaseHelper.instance.rawQuery('''
        SELECT m.*, c.name as category_name, c.icon as category_icon
        FROM menu_items m
        LEFT JOIN categories c ON m.category_id = c.id
        WHERE (m.branch_id = ? OR m.branch_id IS NULL) AND m.is_active = 1
        ORDER BY c.sort_order ASC, m.sort_order ASC, m.name ASC
      ''', [branchId]);

      if (_isReordering) {
        debugPrint('📊 [MENU] Sync BLOCKED — isReordering=true');
        return;
      }
      _menuItems = results.map((e) => MenuItemModel.fromMap(e)).toList();
      debugPrint('📊 [MENU] ✅ Synced: ${_menuItems.length} items');
      notifyListeners();
    } catch (e) {
      debugPrint('📊 [MENU] Supabase sync error: $e');
    }
  }

  /// Ambil stok hari ini dari Supabase (get_menu_stock_today) dan update
  /// kolom has_stock + stock di SQLite lokal, agar _MenuCard otomatis
  /// memblokir/menggreykan item yang stock_sisa = 0.
  ///
  /// Dipanggil dari CashierScreen.initState setelah loadData().
  Future<void> syncStockToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      if (branchId.isEmpty) {
        debugPrint('📦 [STOCK] branchId kosong, skip syncStockToday');
        return;
      }

      debugPrint('📦 [STOCK] syncStockToday → branchId=$branchId');

      final rows = await SupabaseConfig.client
          .rpc('get_menu_stock_today', params: {'p_branch_id': branchId});

      if (rows == null || rows is! List || rows.isEmpty) {
        debugPrint('📦 [STOCK] Tidak ada data stok hari ini');
        return;
      }

      debugPrint('📦 [STOCK] ${rows.length} menu punya data stok');

      // Reset semua has_stock = 0 dulu (menu tanpa row stok = tidak dibatasi stok)
      await DatabaseHelper.instance.rawUpdate(
        'UPDATE menu_items SET has_stock = 0, stock = 0 WHERE branch_id = ?',
        [branchId],
      );

      for (final row in rows) {
        final menuName    = row['menu_name']?.toString() ?? '';
        final stockSisa   = (row['stock_sisa'] as num?)?.toInt() ?? 0;
        final hasStock    = 1; // ada di menu_stock → dikontrol stok
        // stock_sisa < 0 bisa terjadi jika oversell; perlakukan sebagai 0
        final stockValue  = stockSisa < 0 ? 0 : stockSisa;

        // Update berdasarkan nama menu (sesuai cara sync Supabase → SQLite)
        final affected = await DatabaseHelper.instance.rawUpdate(
          'UPDATE menu_items SET has_stock = ?, stock = ? '
              'WHERE branch_id = ? AND LOWER(name) = LOWER(?)',
          [hasStock, stockValue, branchId, menuName],
        );

        debugPrint('📦 [STOCK] "$menuName" → sisa=$stockValue (updated $affected rows)');
      }

      // Reload menu items dari SQLite agar UI terupdate
      final results = await DatabaseHelper.instance.rawQuery('''
        SELECT m.*, c.name as category_name, c.icon as category_icon
        FROM menu_items m
        LEFT JOIN categories c ON m.category_id = c.id
        WHERE (m.branch_id = ? OR m.branch_id IS NULL)
        ORDER BY c.sort_order ASC, m.sort_order ASC, m.name ASC
      ''', [branchId]);

      _menuItems = results.map((e) => MenuItemModel.fromMap(e)).toList();
      debugPrint('📦 [STOCK] ✅ syncStockToday selesai, ${_menuItems.length} menu dimuat ulang');
      _stockLoadDone = true;
      notifyListeners();
    } catch (e) {
      debugPrint('📦 [STOCK] syncStockToday error: $e');
      // Non-fatal: kasir tetap bisa transaksi meski sync stok gagal
      _stockLoadDone = true;
      notifyListeners();
    }
  }

  // Sync menu item ke Supabase setelah add/update
  Future<void> _syncItemToSupabase(MenuItemModel item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      final ownerId   = prefs.getString(AppConstants.keyOwnerId) ?? '';

      // Kalau owner tidak punya branch_id, ambil dari item.branchId
      if (branchId.isEmpty) branchId = item.branchId ?? '';

      // Kalau masih kosong dan ada ownerId, ambil semua cabang owner
      // dan sync menu ke cabang yang dipilih (ambil dari item.branchId)
      if (branchId.isEmpty && ownerId.isNotEmpty) {
        debugPrint('📊 [MENU] owner tidak punya branch_id, skip Supabase sync');
        debugPrint('📊 [MENU] Pastikan pilih cabang dulu sebelum tambah menu');
        return;
      }

      if (branchId.isEmpty) {
        debugPrint('📊 [MENU] branchId kosong, skip sync');
        return;
      }

      // Cek apakah menu dengan nama yang sama sudah ada di cabang ini
      final existing = await SupabaseConfig.client
          .from('menu_items')
          .select('id')
          .eq('branch_id', branchId)
          .eq('name', item.name)
          .maybeSingle();

      if (existing != null) {
        // Update
        await SupabaseConfig.client
            .from('menu_items')
            .update({
          'description':  item.description ?? '',
          'price':        item.price,
          'image_path':   item.imagePath ?? '',
          'is_available': item.isActive,
        })
            .eq('id', existing['id']);
        debugPrint('📊 [MENU] ✅ Item updated in Supabase: ${item.name}');
      } else {
        // Insert baru
        await SupabaseConfig.client.from('menu_items').insert({
          'branch_id':    branchId,
          'name':         item.name,
          'description':  item.description ?? '',
          'price':        item.price,
          'image_path':   item.imagePath ?? '',
          'is_available': item.isActive,
        });
        debugPrint('📊 [MENU] ✅ Item inserted to Supabase: ${item.name}');
      }
    } catch (e) {
      debugPrint('📊 [MENU] Supabase sync error: $e');
    }
  }

  // Upload semua menu dari SQLite ke Supabase
  Future<Map<String, int>> syncAllMenuToSupabase() async {
    int success = 0, failed = 0, skipped = 0;
    try {
      final prefs    = await SharedPreferences.getInstance();
      final ownerId  = prefs.getString(AppConstants.keyOwnerId) ?? '';

      // Ambil semua cabang milik owner
      if (ownerId.isEmpty) {
        debugPrint('📊 [MENU-SYNC] ownerId kosong');
        return {'success': 0, 'failed': 0, 'skipped': 0, 'error': 1};
      }

      final branches = await SupabaseConfig.client
          .from('branches')
          .select('id, name')
          .eq('owner_id', ownerId)
          .eq('is_active', true);

      if (branches.isEmpty) {
        debugPrint('📊 [MENU-SYNC] tidak ada cabang');
        return {'success': 0, 'failed': 0, 'skipped': 0};
      }

      // Ambil semua menu dari SQLite
      final allMenus = await DatabaseHelper.instance.rawQuery(
          'SELECT * FROM menu_items WHERE is_active = 1');

      debugPrint('📊 [MENU-SYNC] ${allMenus.length} menu di SQLite, ${branches.length} cabang');

      for (final menu in allMenus) {
        // Tentukan branch_id: pakai yang ada di menu, atau default cabang pertama
        String targetBranchId = menu['branch_id']?.toString() ?? '';
        if (targetBranchId.isEmpty) {
          targetBranchId = branches.first['id'].toString();
        }

        try {
          await SupabaseConfig.client.from('menu_items').upsert({
            'branch_id':    targetBranchId,
            'name':         menu['name'],
            'description':  menu['description'] ?? '',
            'price':        (menu['price'] as num?)?.toDouble() ?? 0,
            'is_available': (menu['is_active'] as int? ?? 1) == 1,
          }, onConflict: 'branch_id,name');
          success++;
          debugPrint('📊 [MENU-SYNC] ✅ ${menu['name']}');
        } catch (e) {
          failed++;
          debugPrint('📊 [MENU-SYNC] ❌ ${menu['name']}: $e');
        }
      }

      // Kalau menu tidak punya branch_id, duplikasi ke semua cabang
      final menusNoBranch = allMenus.where(
              (m) => (m['branch_id'] ?? '').toString().isEmpty).toList();
      if (menusNoBranch.isNotEmpty) {
        for (final branch in branches) {
          final branchId = branch['id'].toString();
          for (final menu in menusNoBranch) {
            try {
              await SupabaseConfig.client.from('menu_items').upsert({
                'branch_id':    branchId,
                'name':         menu['name'],
                'description':  menu['description'] ?? '',
                'price':        (menu['price'] as num?)?.toDouble() ?? 0,
                'is_available': true,
              }, onConflict: 'branch_id,name');
            } catch (_) {}
          }
        }
      }

      debugPrint('📊 [MENU-SYNC] Done: success=$success failed=$failed');
    } catch (e) {
      debugPrint('📊 [MENU-SYNC] Fatal: $e');
    }
    return {'success': success, 'failed': failed, 'skipped': skipped};
  }

  void selectCategory(int? categoryId) {
    _selectedCategoryId = categoryId;
    notifyListeners();
  }

  // Update urutan menu setelah drag-and-drop
  Future<void> reorderMenuItems(List<MenuItemModel> reorderedItems) async {
    debugPrint('🔀 [REORDER] START — ${reorderedItems.map((e) => e.name).toList()}');
    _isReordering = true;
    _lastReorderTime = DateTime.now();

    _menuItems = reorderedItems;
    notifyListeners();
    debugPrint('🔀 [REORDER] State updated, isReordering=$_isReordering');

    try {
      // Simpan sort_order ke SQLite pakai name+branch karena id mungkin null
      int saved = 0;
      for (int i = 0; i < reorderedItems.length; i++) {
        final item = reorderedItems[i];
        int rows = 0;
        if (item.id != null) {
          // Update by id (paling reliable)
          rows = await DatabaseHelper.instance.rawUpdate(
              'UPDATE menu_items SET sort_order = ? WHERE id = ?',
              [i, item.id]);
        }
        if (rows == 0) {
          // Fallback: update by name (kalau id null)
          rows = await DatabaseHelper.instance.rawUpdate(
              'UPDATE menu_items SET sort_order = ? WHERE name = ?',
              [i, item.name]);
        }
        if (rows > 0) saved++;
        debugPrint('🔀 [REORDER] item[$i] id=${item.id} name=${item.name} rows=$rows');
      }
      debugPrint('📊 [MENU] ✅ Order saved locally: $saved/${reorderedItems.length} items');
      // Verifikasi: cek sort_order yang tersimpan di SQLite
      final check = await DatabaseHelper.instance.rawQuery(
          'SELECT id, name, sort_order FROM menu_items ORDER BY sort_order ASC LIMIT 5');
      debugPrint('🔀 [VERIFY] SQLite sort_order: ${check.map((r) => "${r['name']}=${r['sort_order']}").toList()}');

      // Sync sort_order ke Supabase
      final prefs = await SharedPreferences.getInstance();
      String branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      // Kalau owner tidak punya branch_id, ambil dari item pertama
      if (branchId.isEmpty && reorderedItems.isNotEmpty) {
        branchId = reorderedItems.first.branchId ?? '';
      }
      if (branchId.isNotEmpty) {
        for (int i = 0; i < reorderedItems.length; i++) {
          final item = reorderedItems[i];
          if (item.id == null) continue;
          try {
            await SupabaseConfig.client
                .from('menu_items')
                .update({'sort_order': i})
                .eq('id', item.id!);
          } catch (_) {}
        }
        debugPrint('📊 [MENU] ✅ Order synced to Supabase');
      }
    } catch (e) {
      debugPrint('📊 [MENU] reorder error: $e');
    } finally {
      _isReordering = false;
      debugPrint('🔀 [REORDER] DONE — isReordering=false');
      // State sudah di-set dari awal reorder, tidak perlu reload ulang
    }
  }

  Future<void> _reloadFromSQLite() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      List<Map<String,dynamic>> results;
      if (branchId.isNotEmpty) {
        results = await DatabaseHelper.instance.rawQuery("""
          SELECT m.*, c.name as category_name, c.icon as category_icon
          FROM menu_items m
          LEFT JOIN categories c ON m.category_id = c.id
          WHERE (m.branch_id = ? OR m.branch_id IS NULL) AND m.is_active = 1
          ORDER BY c.sort_order ASC, m.sort_order ASC, m.name ASC
        """, [branchId]);
      } else {
        results = await DatabaseHelper.instance.rawQuery("""
          SELECT m.*, c.name as category_name, c.icon as category_icon
          FROM menu_items m
          LEFT JOIN categories c ON m.category_id = c.id
          ORDER BY c.sort_order ASC, m.sort_order ASC, m.name ASC
        """);
      }
      _menuItems = results.map((e) => MenuItemModel.fromMap(e)).toList();
      debugPrint('🔀 [REORDER] Confirm from SQLite: ${_menuItems.map((e) => e.name).toList()}');
      notifyListeners();
    } catch (e) {
      debugPrint('🔀 [REORDER] reload error: $e');
    }
  }

  // Category CRUD
  Future<bool> addCategory(String name, String icon) async {
    try {
      await DatabaseHelper.instance.insert('categories', {
        'name': name,
        'icon': icon,
        'sort_order': _categories.length,
        'is_active': 1,
      });
      await loadCategories();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateCategory(int id, String name, String icon, bool isActive) async {
    try {
      await DatabaseHelper.instance.update(
        'categories',
        {'name': name, 'icon': icon, 'is_active': isActive ? 1 : 0},
        'id = ?',
        [id],
      );
      await loadCategories();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteCategory(int id) async {
    try {
      // BUG 22 FIX: Hanya cek item yang AKTIF. Item nonaktif (is_active=0)
      // tidak menghalangi penghapusan kategori.
      final items = await DatabaseHelper.instance.query(
        'menu_items',
        where: 'category_id = ? AND is_active = 1',
        whereArgs: [id],
      );
      if (items.isNotEmpty) return false; // Can't delete category with active items
      await DatabaseHelper.instance.delete('categories', 'id = ?', [id]);
      await loadCategories();
      return true;
    } catch (e) {
      debugPrint('deleteCategory error: $e');
      return false;
    }
  }

  // Menu Item CRUD
  Future<bool> addMenuItem(MenuItemModel item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      // Buat item baru dengan branchId
      final itemWithBranch = MenuItemModel(
        categoryId: item.categoryId,
        branchId: branchId.isNotEmpty ? branchId : item.branchId,
        name: item.name,
        description: item.description,
        price: item.price,
        imagePath: item.imagePath,
        isActive: item.isActive,
        hasStock: item.hasStock,
        stock: item.stock,
        createdAt: item.createdAt,
      );
      await DatabaseHelper.instance.insert('menu_items', itemWithBranch.toMap());
      // Sync ke Supabase di background
      _syncItemToSupabase(itemWithBranch);
      await loadMenuItems();
      return true;
    } catch (e) {
      debugPrint('addMenuItem error: $e');
      return false;
    }
  }

  Future<bool> updateMenuItem(MenuItemModel item) async {
    try {
      await DatabaseHelper.instance.update(
        'menu_items',
        item.toMap(),
        'id = ?',
        [item.id],
      );
      _syncItemToSupabase(item); // sync to Supabase in background
      await loadMenuItems();
      return true;
    } catch (e) {
      debugPrint('updateMenuItem error: $e');
      return false;
    }
  }

  Future<bool> deleteMenuItem(int id) async {
    try {
      // Get item before delete to get branch_id and supabase_id
      final items = await DatabaseHelper.instance.query('menu_items', where: 'id = ?', whereArgs: [id]);
      await DatabaseHelper.instance.delete('menu_items', 'id = ?', [id]);

      // BUG 21 FIX: Soft delete di Supabase menggunakan branch_id + name hanya
      // sebagai fallback. Jika ada supabase_id tersimpan, gunakan itu.
      // Ini mencegah penghapusan semua item bernama sama.
      if (items.isNotEmpty) {
        final branchId  = items.first['branch_id']?.toString() ?? '';
        final itemName  = items.first['name']?.toString() ?? '';
        final supaId    = items.first['supabase_id']?.toString() ?? ''; // jika ada

        if (branchId.isNotEmpty) {
          try {
            if (supaId.isNotEmpty) {
              // Cara terbaik: gunakan ID unik
              await SupabaseConfig.client
                  .from('menu_items')
                  .update({'is_available': false})
                  .eq('id', supaId);
            } else if (itemName.isNotEmpty) {
              // Fallback: filter ketat dengan branch_id + name + created_at
              // untuk meminimalkan false positives
              final createdAt = items.first['created_at']?.toString() ?? '';
              var query = SupabaseConfig.client
                  .from('menu_items')
                  .update({'is_available': false})
                  .eq('branch_id', branchId)
                  .eq('name', itemName);
              if (createdAt.isNotEmpty) {
                query = query.eq('created_at', createdAt);
              }
              await query;
            }
          } catch (e) {
            debugPrint('deleteMenuItem Supabase sync error: $e');
          }
        }
      }
      await loadMenuItems();
      return true;
    } catch (e) {
      debugPrint('deleteMenuItem error: $e');
      return false;
    }
  }

  Future<bool> toggleMenuItemStatus(int id, bool isActive) async {
    try {
      await DatabaseHelper.instance.update(
        'menu_items',
        {'is_active': isActive ? 1 : 0},
        'id = ?',
        [id],
      );
      await loadMenuItems();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateStock(int id, int stock) async {
    try {
      await DatabaseHelper.instance.update(
        'menu_items',
        {'stock': stock},
        'id = ?',
        [id],
      );
      await loadMenuItems();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Hapus cache stok harian — reset has_stock & stock ke 0 untuk semua item
  /// di cabang aktif, lalu reload menu. Dipanggil saat logout/ganti shift
  /// agar stok tidak stale di sesi berikutnya.
  Future<void> clearStockCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      if (branchId.isNotEmpty) {
        await DatabaseHelper.instance.rawUpdate(
          'UPDATE menu_items SET has_stock = 0, stock = 0 WHERE branch_id = ?',
          [branchId],
        );
        debugPrint('📦 [STOCK] clearStockCache → reset stok untuk branch=$branchId');
      } else {
        await DatabaseHelper.instance.rawUpdate(
          'UPDATE menu_items SET has_stock = 0, stock = 0',
          [],
        );
        debugPrint('📦 [STOCK] clearStockCache → reset stok semua menu');
      }
      await loadMenuItems();
    } catch (e) {
      debugPrint('📦 [STOCK] clearStockCache error: $e');
    }
  }

  List<MenuItemModel> searchMenu(String query) {
    final q = query.toLowerCase();
    return _menuItems.where((item) =>
    item.name.toLowerCase().contains(q) ||
        (item.description?.toLowerCase().contains(q) ?? false)
    ).toList();
  }
}