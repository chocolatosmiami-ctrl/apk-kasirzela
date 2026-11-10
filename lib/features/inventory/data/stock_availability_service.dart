import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/services/offline_order_sync_service.dart';
import '../../../core/services/recipe_stock.dart';

/// Ketersediaan menu berdasarkan stok bahan harian.
///
/// Sumber data (sama dengan yang dipakai dashboard & server saat potong stok):
/// - `get_menu_stock_today(branch)` → stok bahan hari ini (menu_stock)
/// - `get_menu_components(branch)`  → link menu → bahan (menu_stock_components)
///
/// Aturan AKTIF kalau cabang sudah memakai sistem stok — punya minimal 1 link
/// menu↔bahan (menu_stock_components) ATAU sudah set stok hari ini.
/// Cabang aktif: menu tanpa link dikunci "Resep Belum Diset", menu yang bahannya
/// belum diset stok hari ini dikunci "Stok Bahan Belum Diset".
/// Cabang yang sama sekali belum pakai sistem stok tidak dikunci.
class StockAvailability {
  final bool enforced;
  final String? unavailableReason;
  final Map<String, double> stock; // bahanKey → sisa
  final Map<String, List<MapEntry<String, double>>>
  comps; // menuKey → [(bahanKey, qty)]

  const StockAvailability({
    required this.enforced,
    required this.stock,
    required this.comps,
    this.unavailableReason,
  });

  static const empty = StockAvailability(enforced: false, stock: {}, comps: {});

  static String keyOf(String s) => s.toLowerCase().trim();

  int? portionsFor(String menuName) => !enforced || unavailableReason != null
      ? null : recipePortions(menuName, stock, comps);

  /// Alasan menu dikunci (teks overlay), atau null kalau boleh dijual.
  String? reasonFor(String menuName) {
    if (unavailableReason != null) return unavailableReason;
    if (!enforced) return null;
    final k = keyOf(menuName);

    // 1. Menu yang stoknya dihitung langsung (nama menu = nama bahan)
    final direct = stock[k];
    if (direct != null && direct <= 0) return 'Habis\nHari Ini';

    // 2. Menu yang punya resep → cek tiap bahan
    final list = comps[k] ?? const <MapEntry<String, double>>[];
    if (list.isNotEmpty) {
      var missing = false;
      for (final c in recipeNeeds(menuName, stock, comps).entries) {
        if (!c.value.isFinite || c.value <= 0) return 'Resep\nTidak Valid';
        final s = stock[c.key];
        if (s == null) {
          missing = true;
        } else if (s < c.value) {
          return 'Bahan\nHabis';
        }
      }
      if (missing) return 'Stok Bahan Hari Ini\nBelum Diset';
      return null;
    }

    // 3. Tidak punya resep & tidak punya stok langsung
    if (direct == null) return 'Resep\nBelum Diset';
    return null;
  }

  /// Validasi seluruh keranjang (menjumlah kebutuhan bahan lintas item).
  /// Return (namaMenu, detail) item pertama yang bermasalah, atau null kalau aman.
  MapEntry<String, String>? validateCart(List<MapEntry<String, num>> items) {
    if (!enforced) return null;
    final need = <String, double>{};
    final usedBy = <String, String>{}; // bahanKey → nama menu pemakai pertama
    for (final it in items) {
      final reason = reasonFor(it.key);
      if (reason != null) {
        return MapEntry(it.key, reason.replaceAll('\n', ' '));
      }
      final k = keyOf(it.key);
      final qty = it.value.toDouble();
      if (stock.containsKey(k) && !(comps[k] ?? const <MapEntry<String, double>>[]).any((c) => c.key == k)) {
        need[k] = (need[k] ?? 0) + qty;
        usedBy.putIfAbsent(k, () => it.key);
      }
      for (final c in comps[k] ?? const <MapEntry<String, double>>[]) {
        need[c.key] = (need[c.key] ?? 0) + c.value * qty;
        usedBy.putIfAbsent(c.key, () => it.key);
      }
    }
    for (final e in need.entries) {
      final sisa = stock[e.key];
      if (sisa != null && sisa < e.value) {
        return MapEntry(
          usedBy[e.key] ?? e.key,
          'Stok ${e.key} tidak cukup (sisa ${_fmt(sisa)}, butuh ${_fmt(e.value)})',
        );
      }
    }
    return null;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class StockAvailabilityService {
  StockAvailabilityService._();

  static String _day() => DateTime.now()
      .toUtc()
      .add(const Duration(hours: 7))
      .toIso8601String()
      .substring(0, 10);

  static Future<StockAvailability> _reservePending(
    StockAvailability snapshot,
    String branchId,
    String capturedAt,
  ) async {
    final stock = Map<String, double>.from(snapshot.stock);
    // Include acknowledgements since this snapshot as well: otherwise an online
    // sale followed by disconnect would resurrect stock in the offline cache.
    final pending = await OfflineOrderSyncService.pendingItems(branchId, capturedAt);
    for (final item in pending) {
      final key = StockAvailability.keyOf(item['item_name'].toString());
      final qty = (item['quantity'] as num).toDouble();
      if (stock.containsKey(key) && !(snapshot.comps[key] ?? const <MapEntry<String, double>>[]).any((c) => c.key == key)) {
        stock[key] = stock[key]! - qty;
      }
      for (final comp
          in snapshot.comps[key] ?? const <MapEntry<String, double>>[]) {
        if (stock.containsKey(comp.key))
          stock[comp.key] = stock[comp.key]! - qty * comp.value;
      }
    }
    return StockAvailability(
      enforced: snapshot.enforced,
      stock: stock,
      comps: snapshot.comps,
    );
  }

  /// Reuse only today's branch-scoped snapshot and subtract unacknowledged sales.
  static Future<StockAvailability> load(String branchId) async {
    if (branchId.isEmpty) return const StockAvailability(
      enforced: true, stock: {}, comps: {},
      unavailableReason: 'Pilih cabang\nuntuk memuat stok');
    final capturedAt = DateTime.now().toUtc().toIso8601String();
    try {
      final client = SupabaseConfig.client;
      final dynamic stockRes = await client
          .rpc('get_menu_stock_today', params: {'p_branch_id': branchId})
          .timeout(const Duration(seconds: 4));
      final dynamic compRes = await client
          .rpc('get_menu_components', params: {'p_branch_id': branchId})
          .timeout(const Duration(seconds: 4));
      if (stockRes is! List || compRes is! List)
        throw StateError('Respons stok tidak valid');

      final stock = <String, double>{};
      for (final r in (stockRes is List ? stockRes : const [])) {
        final key = StockAvailability.keyOf(
          (r['menu_name_key'] ?? r['menu_name'] ?? '').toString(),
        );
        if (key.isEmpty) continue;
        stock[key] = (r['stock_sisa'] as num?)?.toDouble() ?? 0;
      }

      final comps = <String, List<MapEntry<String, double>>>{};
      for (final r in (compRes is List ? compRes : const [])) {
        final menuKey = StockAvailability.keyOf(
          (r['menu_name_key'] ?? '').toString(),
        );
        final bahanKey = StockAvailability.keyOf(
          (r['component_key'] ?? '').toString(),
        );
        if (menuKey.isEmpty || bahanKey.isEmpty) continue;
        final qty = (r['qty_per_order'] as num?)?.toDouble() ?? 1;
        comps.putIfAbsent(menuKey, () => []).add(MapEntry(bahanKey, qty));
      }

      debugPrint(
        '📦 [AVAIL] branch=$branchId stok=${stock.length} resep=${comps.length} '
        'enforced=${stock.isNotEmpty || comps.isNotEmpty}',
      );
      final snapshot = StockAvailability(
        enforced: stock.isNotEmpty || comps.isNotEmpty,
        stock: stock,
        comps: comps,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ingredient_snapshot_$branchId',
        jsonEncode({
          'day': _day(),
          'captured_at': capturedAt,
          'stock': stock,
          'comps': comps.map(
            (k, v) => MapEntry(
              k,
              v.map((e) => {'key': e.key, 'qty': e.value}).toList(),
            ),
          ),
        }),
      );
      return await _reservePending(snapshot, branchId, capturedAt);
    } catch (e) {
      debugPrint('📦 [AVAIL] load error → local snapshot: $e');
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ingredient_snapshot_$branchId');
      if (raw != null) {
        try {
          final saved = jsonDecode(raw) as Map;
          if (saved['day'] == _day()) {
            final stock = (saved['stock'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            );
            final comps = (saved['comps'] as Map).map(
              (k, v) => MapEntry(
                k.toString(),
                (v as List)
                    .map(
                      (e) => MapEntry(
                        e['key'] as String,
                        (e['qty'] as num).toDouble(),
                      ),
                    )
                    .toList(),
              ),
            );
            return await _reservePending(
              StockAvailability(
                enforced: stock.isNotEmpty || comps.isNotEmpty,
                stock: stock,
                comps: comps,
              ),
              branchId,
              saved['captured_at']?.toString() ?? '',
            );
          }
        } catch (_) {
          /* Corrupt cache must never silently unlock menus. */
        }
      }
      return const StockAvailability(
        enforced: true,
        stock: {},
        comps: {},
        unavailableReason: 'Hubungkan internet\nuntuk memuat stok',
      );
    }
  }
}
