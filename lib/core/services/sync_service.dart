import '../utils/app_constants.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';

class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  /// Cek koneksi internet dengan ping nyata (DNS lookup).
  Future<bool> hasInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result == ConnectivityResult.none) return false;
      final lookup = await InternetAddress.lookup(
        'supabase.com',
      ).timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> syncBranchData({bool force = false}) async {
    debugPrint('SyncService: Supabase handles sync automatically');
    return true;
  }

  // ── Laporan admin semua cabang ────────────────────────
  Future<List<Map<String, dynamic>>> getAdminReport(DateTime date) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59);
    return _fetchBranchReport(dayStart, dayEnd);
  }

  Future<List<Map<String, dynamic>>> getAdminReportRange(
      DateTime from, DateTime to) async {
    return _fetchBranchReport(from, to);
  }

  Future<List<Map<String, dynamic>>> _fetchBranchReport(
      DateTime from, DateTime to) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(AppConstants.keyEmail) ?? '';
      final role  = prefs.getString(AppConstants.keyRole)  ?? '';

      debugPrint('🔴 [AdminReport] ===== START _fetchBranchReport =====');
      debugPrint('🔴 [AdminReport] email=$email role=$role');
      debugPrint('🔴 [AdminReport] from=$from to=$to');

      if (email.isEmpty) {
        debugPrint('🔴 [AdminReport] ❌ email KOSONG — return []');
        return [];
      }

      // Kirim DATE saja (YYYY-MM-DD) - RPC yang handle konversi ke UTC WIB
      final fromStr = '${from.year.toString().padLeft(4,'0')}-${from.month.toString().padLeft(2,'0')}-${from.day.toString().padLeft(2,'0')}';
      final toStr   = '${to.year.toString().padLeft(4,'0')}-${to.month.toString().padLeft(2,'0')}-${to.day.toString().padLeft(2,'0')}';

      debugPrint('🔴 [AdminReport] fromStr=$fromStr');
      debugPrint('🔴 [AdminReport] toStr=$toStr');
      debugPrint('🔴 [AdminReport] Calling RPC get_owner_report_by_email...');

      final client = SupabaseConfig.client;
      final summaryRaw = await client.rpc('get_owner_report_by_email', params: {
        'p_email': email,
        'p_from':  fromStr,
        'p_to':    toStr,
      });

      debugPrint('🔴 [AdminReport] RPC result type: ${summaryRaw.runtimeType}');
      debugPrint('🔴 [AdminReport] RPC result: $summaryRaw');

      if (summaryRaw == null) {
        debugPrint('🔴 [AdminReport] ❌ RPC returned null');
        return [];
      }

      final List<dynamic> summaryList = summaryRaw is List ? summaryRaw : [];
      debugPrint('📊 [AdminReport] ${summaryList.length} cabang dari RPC');

      final List<Map<String, dynamic>> result = [];

      for (final row in summaryList) {
        final branchId   = row['branch_id']?.toString() ?? '';
        final branchName = row['branch_name']?.toString() ?? '';
        final totalRevenue = (row['total_revenue'] as num?)?.toDouble() ?? 0;
        final totalExpense = (row['total_expense'] as num?)?.toDouble() ?? 0;
        final totalOrders  = (row['total_orders']  as num?)?.toInt()    ?? 0;

        debugPrint('📊 [AdminReport] $branchName: trx=$totalOrders revenue=$totalRevenue');

        // Top menu per cabang - selalu load tanpa cek totalOrders
        List<Map<String, dynamic>> topMenus = [];
        if (branchId.isNotEmpty) {
          try {
            final menus = await client.rpc('get_branch_top_menus', params: {
              'p_branch_id': branchId,
              'p_from':      fromStr,
              'p_to':        toStr,
              'p_limit':     5,
            });
            if (menus is List) {
              topMenus = menus
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            }
          } catch (e) {
            debugPrint('📊 [AdminReport] topMenus error: $e');
          }
        }

        // Kasir per cabang - selalu load tanpa cek totalOrders
        List<Map<String, dynamic>> kasirList = [];
        if (branchId.isNotEmpty) {
          try {
            final kasir = await client.rpc('get_branch_kasir_summary', params: {
              'p_branch_id': branchId,
              'p_from':      fromStr,
              'p_to':        toStr,
            });
            if (kasir is List) {
              kasirList = kasir
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            }
          } catch (e) {
            debugPrint('📊 [AdminReport] kasir error: $e');
          }
        }

        result.add({
          'branch_id':       branchId,
          'branch_name':     branchName,
          'total_revenue':   totalRevenue,
          'total_expense':   totalExpense,
          'profit':          totalRevenue - totalExpense,
          'total_orders':    totalOrders,
          'cash_amount':     (row['cash_amount']     as num?)?.toDouble() ?? 0.0,
          'qris_amount':     (row['qris_amount']     as num?)?.toDouble() ?? 0.0,
          'transfer_amount': (row['transfer_amount'] as num?)?.toDouble() ?? 0.0,
          'top_menus':       topMenus,
          'per_kasir':       kasirList,
        });
      }

      return result;
    } catch (e) {
      debugPrint('📊 [AdminReport] _fetchBranchReport error: $e');
      return [];
    }
  }
}
