import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/app_constants.dart';

class BahanBakuModel {
  final String id;         // master_bahan_baku.id
  final String ownerId;
  final String name;
  final String satuan;     // satuan_resep
  final String satuanBeli;
  final double hargaBeli;
  final String? gudangStokId;
  double stokSisa;

  BahanBakuModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.satuan,
    required this.satuanBeli,
    required this.hargaBeli,
    this.gudangStokId,
    required this.stokSisa,
  });

  bool get isLow => stokSisa > 0 && stokSisa <= 5;
  bool get isOut => stokSisa <= 0;

  // Alias kompatibilitas
  String get unit => satuan;
  double? get currentStock => stokSisa;
  double? get minStock => null;
}

class InventoryProvider extends ChangeNotifier {
  final _db = Supabase.instance.client;

  List<BahanBakuModel> _items = [];
  List<BahanBakuModel> get items => _items;
  List<BahanBakuModel> get ingredients => _items;

  List<BahanBakuModel> get lowStockItems =>
      _items.where((i) => i.isLow).toList();
  List<BahanBakuModel> get outOfStockItems =>
      _items.where((i) => i.isOut).toList();
  bool get hasLowStock => _items.any((i) => i.isLow || i.isOut);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _ownerId = '';
  String get ownerId => _ownerId; // untuk debug
  String _branchId = '';
  String _userName = '';

  List<int> get unavailableMenuIds => [];

  // ── Load: master_bahan_baku + menu_stock hari ini ─────────
  Future<void> loadIngredients() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      _userName = prefs.getString(AppConstants.keyKasirName) ?? 'Kasir';

      // Ambil owner_id dari branches
      if (_branchId.isNotEmpty) {
        try {
          final branchRes = await _db
              .from('branches')
              .select('owner_id')
              .eq('id', _branchId)
              .single();
          _ownerId = branchRes['owner_id']?.toString() ?? '';
          debugPrint('✅ Inventory owner_id: $_ownerId branch: $_branchId');
        } catch (e) {
          debugPrint('❌ get owner_id: $e');
        }
      }

      if (_ownerId.isEmpty) {
        _items = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Load master bahan baku milik owner
      final bbRes = await _db
          .from('master_bahan_baku')
          .select('id, name, satuan_resep, harga_beli')
          .eq('owner_id', _ownerId)
          .eq('is_active', true)
          .order('name');

      // Load menu_stock hari ini untuk branch ini
      final today = DateTime.now().toIso8601String().substring(0, 10);
      Map<String, double> stokMap = {};
      try {
        final msRes = await _db
            .from('menu_stock')
            .select('menu_name, stock_sisa')
            .eq('branch_id', _branchId)
            .eq('stock_date', today);
        for (final ms in (msRes as List)) {
          final key = (ms['menu_name'] as String).toLowerCase().trim();
          stokMap[key] = (ms['stock_sisa'] as num?)?.toDouble() ?? 0;
        }
        debugPrint('✅ menu_stock: ${stokMap.length} items untuk $_branchId');
      } catch (e) {
        debugPrint('❌ menu_stock load: $e');
      }

      // Juga cek gudang_stok sebagai fallback
      Map<String, double> gudangMap = {};
      try {
        final gsRes = await _db
            .from('gudang_stok')
            .select('bahan_baku_id, stok_sisa')
            .eq('owner_id', _ownerId);
        for (final gs in (gsRes as List)) {
          gudangMap[gs['bahan_baku_id'].toString()] =
              (gs['stok_sisa'] as num?)?.toDouble() ?? 0;
        }
      } catch (_) {}

      _items = (bbRes as List).map((bb) {
        final namaKey = (bb['name'] as String).toLowerCase().trim();
        // Prioritas: menu_stock hari ini → gudang_stok → 0
        final stok = stokMap[namaKey] ??
            gudangMap[bb['id'].toString()] ?? 0;
        return BahanBakuModel(
          id: bb['id'].toString(),
          ownerId: _ownerId,
          name: bb['name'].toString(),
          satuan: bb['satuan_resep']?.toString() ?? 'pcs',
          satuanBeli: 'pcs',
          hargaBeli: (bb['harga_beli'] ?? 0).toDouble(),
          stokSisa: stok,
        );
      }).toList();

      debugPrint('✅ Inventory: ${_items.length} bahan, '
          '${_items.where((i) => i.stokSisa > 0).length} sudah diset');
    } catch (e) {
      debugPrint('❌ loadIngredients: $e');
      _items = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Tambah stok → update gudang_stok ────────────────────
  Future<bool> tambahStok({
    required String bahanBakuId,
    required String namaBahan,
    required double jumlah,
    String keterangan = 'Restok dari APK',
  }) async {
    try {
      final item = _items.where((i) => i.id == bahanBakuId).firstOrNull;
      if (item == null) return false;

      final stokBaru = item.stokSisa + jumlah;

      // Cek apakah gudang_stok sudah ada
      final existing = await _db
          .from('gudang_stok')
          .select('id')
          .eq('bahan_baku_id', bahanBakuId)
          .eq('owner_id', _ownerId)
          .maybeSingle();

      if (existing != null) {
        await _db.from('gudang_stok').update({
          'stok_sisa': stokBaru,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existing['id']);
      } else {
        await _db.from('gudang_stok').insert({
          'bahan_baku_id': bahanBakuId,
          'owner_id': _ownerId,
          'stok_sisa': stokBaru,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      await _writeLog(
        bahanName: namaBahan,
        type: 'tambah',
        jumlah: jumlah,
        stokBefore: item.stokSisa,
        stokAfter: stokBaru,
      );

      item.stokSisa = stokBaru;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ tambahStok: $e');
      return false;
    }
  }

  // ── Set/koreksi stok ─────────────────────────────────────
  Future<bool> setStok({
    required String bahanBakuId,
    required String namaBahan,
    required double stokBaru,
  }) async {
    try {
      final item = _items.where((i) => i.id == bahanBakuId).firstOrNull;
      if (item == null) return false;

      final stokLama = item.stokSisa;

      final existing = await _db
          .from('gudang_stok')
          .select('id')
          .eq('bahan_baku_id', bahanBakuId)
          .eq('owner_id', _ownerId)
          .maybeSingle();

      if (existing != null) {
        await _db.from('gudang_stok').update({
          'stok_sisa': stokBaru,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existing['id']);
      } else {
        await _db.from('gudang_stok').insert({
          'bahan_baku_id': bahanBakuId,
          'owner_id': _ownerId,
          'stok_sisa': stokBaru,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      await _writeLog(
        bahanName: namaBahan,
        type: 'opname',
        jumlah: stokBaru - stokLama,
        stokBefore: stokLama,
        stokAfter: stokBaru,
      );

      item.stokSisa = stokBaru;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ setStok: $e');
      return false;
    }
  }

  Future<void> _writeLog({
    required String bahanName,
    required String type,
    required double jumlah,
    required double stokBefore,
    required double stokAfter,
  }) async {
    try {
      await _db.from('stock_activity_log').insert({
        'branch_id': _branchId,
        'type': type,
        'bahan_name': bahanName,
        'jumlah': jumlah,
        'stok_before': stokBefore,
        'stok_after': stokAfter,
        'created_by': _userName,
        'sender_name': _userName,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('❌ writeLog: $e');
    }
  }

  // ── Stub kompatibilitas ───────────────────────────────────
  Future<bool> isMenuAvailable(int menuItemId) async => true;
  bool isMenuAvailableByName(String n) => true;
  Future<bool> addIngredient(dynamic i) async => false;
  Future<bool> updateIngredient(dynamic i) async => false;
  Future<bool> updateStock(dynamic id, double s) async => false;
  Future<bool> addStock(dynamic id, double a) async => false;
  Future<bool> deleteIngredient(dynamic id) async => false;
  Future<List<dynamic>> getMenuIngredients(int id) async => [];
  Future<bool> linkIngredient(dynamic l) async => false;
  Future<bool> unlinkIngredient(dynamic id) async => false;
  Future<void> deductIngredients(int id, int qty) async {}
  Future<bool> deductStockByMenuName(String n, double q) async => false;
  Future<List<int>> getUnavailableMenuIds() async => [];
  Future<bool> tambahStokByName(String nama, double jumlah) async {
    final item = _items.where(
            (i) => i.name.toLowerCase() == nama.toLowerCase()).firstOrNull;
    if (item == null) return false;
    return tambahStok(bahanBakuId: item.id, namaBahan: nama, jumlah: jumlah);
  }
  Future<bool> setStokByName(String nama, double stokBaru) async {
    final item = _items.where(
            (i) => i.name.toLowerCase() == nama.toLowerCase()).firstOrNull;
    if (item == null) return false;
    return setStok(bahanBakuId: item.id, namaBahan: nama, stokBaru: stokBaru);
  }
}