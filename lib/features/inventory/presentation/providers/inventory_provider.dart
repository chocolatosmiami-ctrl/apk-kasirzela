import '../../../../core/utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/ingredient_model.dart';
import '../../../../core/database/database_helper.dart';

class InventoryProvider extends ChangeNotifier {
  List<IngredientModel> _ingredients = [];
  List<int> _unavailableMenuIds = []; // cache ID menu yang bahan bakunya habis
  bool _isLoading = false;

  List<IngredientModel> get ingredients => _ingredients;
  List<int> get unavailableMenuIds => _unavailableMenuIds;
  List<IngredientModel> get lowStockItems =>
      _ingredients.where((i) => i.isLow && !i.isOut).toList();
  List<IngredientModel> get outOfStockItems =>
      _ingredients.where((i) => i.isOut).toList();
  bool get isLoading => _isLoading;
  bool get hasLowStock => _ingredients.any((i) => i.isLow);

  Future<void> loadIngredients() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      // Filter per email — setiap user punya stok bahan sendiri
      final email = prefs.getString(AppConstants.keyEmail) ?? '';

      List<Map<String,dynamic>> results;
      if (email.isNotEmpty) {
        results = await DatabaseHelper.instance.rawQuery(
          "SELECT * FROM ingredients WHERE (email = ? OR email IS NULL OR email = '') ORDER BY name ASC",
          [email],
        );
      } else {
        results = await DatabaseHelper.instance.query(
          'ingredients', orderBy: 'name ASC',
        );
      }
      _ingredients = results.map((e) => IngredientModel.fromMap(e)).toList();

      // Update cache menu yang tidak bisa dipesan karena bahan habis
      _unavailableMenuIds = await _fetchUnavailableMenuIds();
    } catch (e) {
      debugPrint('loadIngredients error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Query menu yang stok bahannya habis — filter per email user
  Future<List<int>> _fetchUnavailableMenuIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(AppConstants.keyEmail) ?? '';

      final results = await DatabaseHelper.instance.rawQuery('''
        SELECT DISTINCT mi.menu_item_id
        FROM menu_ingredients mi
        JOIN ingredients i ON mi.ingredient_id = i.id
        WHERE i.current_stock < mi.quantity_used
          AND (i.email = ? OR i.email IS NULL OR i.email = '' OR ? = '')
      ''', [email, email]);
      return results.map((r) => r['menu_item_id'] as int).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> addIngredient(IngredientModel ingredient) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Simpan dengan email sebagai identifier per user
      final email = prefs.getString(AppConstants.keyEmail) ?? '';
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      final data = ingredient.toMap();
      if (email.isNotEmpty) data['email'] = email;
      if (branchId.isNotEmpty) data['branch_id'] = branchId;
      await DatabaseHelper.instance.insert('ingredients', data);
      await loadIngredients();
      return true;
    } catch (e) {
      debugPrint('addIngredient error: $e');
      return false;
    }
  }

  Future<bool> updateIngredient(IngredientModel ingredient) async {
    try {
      await DatabaseHelper.instance.update(
        'ingredients', ingredient.toMap(), 'id = ?', [ingredient.id],
      );
      await loadIngredients();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateStock(int id, double newStock) async {
    try {
      await DatabaseHelper.instance.update(
        'ingredients',
        {'current_stock': newStock, 'updated_at': DateTime.now().toIso8601String()},
        'id = ?', [id],
      );
      await loadIngredients();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> addStock(int id, double amount) async {
    // BUG 32 FIX: Gunakan atomic SQL UPDATE alih-alih read-modify-write.
    // Pola lama: baca stok dari memori → hitung baru → UPDATE
    // Jika 2 operasi bersamaan, keduanya baca nilai lama dan saling overwrite.
    // Pola baru: UPDATE SET stock = stock + amount langsung di DB (atomic).
    try {
      final db = await DatabaseHelper.instance.database;
      await db.rawUpdate(
        'UPDATE ingredients SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
        [amount, DateTime.now().toIso8601String(), id],
      );
      await loadIngredients();
      return true;
    } catch (e) {
      debugPrint('addStock error: $e');
      return false;
    }
  }

  Future<bool> deleteIngredient(int id) async {
    try {
      // Remove links first
      await DatabaseHelper.instance.delete(
          'menu_ingredients', 'ingredient_id = ?', [id]);
      await DatabaseHelper.instance.delete('ingredients', 'id = ?', [id]);
      await loadIngredients();
      return true;
    } catch (_) {
      return false;
    }
  }

  // Get ingredients linked to a menu item
  Future<List<MenuIngredientModel>> getMenuIngredients(int menuItemId) async {
    try {
      final results = await DatabaseHelper.instance.rawQuery('''
        SELECT mi.*, i.name as ingredient_name, i.unit
        FROM menu_ingredients mi
        JOIN ingredients i ON mi.ingredient_id = i.id
        WHERE mi.menu_item_id = ?
      ''', [menuItemId]);
      return results.map((e) => MenuIngredientModel.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> linkIngredient(MenuIngredientModel link) async {
    try {
      await DatabaseHelper.instance.insert('menu_ingredients', link.toMap());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlinkIngredient(int menuIngredientId) async {
    try {
      await DatabaseHelper.instance.delete(
          'menu_ingredients', 'id = ?', [menuIngredientId]);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Check if menu item is available based on ingredient stock
  Future<bool> isMenuAvailable(int menuItemId) async {
    try {
      final links = await getMenuIngredients(menuItemId);
      if (links.isEmpty) return true; // No ingredient tracking = always available

      for (final link in links) {
        final ingredient = _ingredients.firstWhere(
          (i) => i.id == link.ingredientId,
          orElse: () => IngredientModel(
            name: '', unit: '', currentStock: 0,
            minStock: 0, updatedAt: '',
          ),
        );
        if (ingredient.currentStock < link.quantityUsed) {
          return false; // Not enough stock
        }
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  // Deduct ingredients when order is placed
  Future<void> deductIngredients(int menuItemId, int qty) async {
    try {
      final links = await getMenuIngredients(menuItemId);
      for (final link in links) {
        final ingredient = _ingredients.firstWhere(
          (i) => i.id == link.ingredientId,
          orElse: () => IngredientModel(
            name: '', unit: '', currentStock: 0,
            minStock: 0, updatedAt: '',
          ),
        );
        if (ingredient.id != null) {
          final newStock = ingredient.currentStock - (link.quantityUsed * qty);
          await updateStock(ingredient.id!, newStock.clamp(0, double.infinity));
        }
      }
    } catch (e) {
      debugPrint('deductIngredients error: $e');
    }
  }

  // Get all unavailable menu items
  Future<List<int>> getUnavailableMenuIds() async {
    try {
      final results = await DatabaseHelper.instance.rawQuery('''
        SELECT DISTINCT mi.menu_item_id
        FROM menu_ingredients mi
        JOIN ingredients i ON mi.ingredient_id = i.id
        WHERE i.current_stock < mi.quantity_used
      ''');
      return results.map((r) => r['menu_item_id'] as int).toList();
    } catch (_) {
      return [];
    }
  }
}
