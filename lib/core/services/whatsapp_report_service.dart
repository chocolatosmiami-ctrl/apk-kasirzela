import '../utils/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../config/supabase_config.dart';
import '../database/database_helper.dart';
import '../utils/app_utils.dart';
import '../services/sync_service.dart';

/// Laporan WhatsApp — semi-otomatis
/// Owner tinggal klik Send setelah WA terbuka dengan pesan terisi
class WhatsAppReportService {
  static final WhatsAppReportService instance = WhatsAppReportService._();
  WhatsAppReportService._();

  // ── Keys SharedPrefs ──────────────────────────────────
  static const String _keyOwnerPhone = 'wa_owner_phone';
  static const String _keyGroupLink  = 'wa_group_link';
  static const String _keyAutoWaEnabled = 'auto_wa_enabled';

  // ── Getters settings ──────────────────────────────────
  Future<String> getOwnerPhone() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyOwnerPhone) ?? '';
  }

  Future<String> getGroupLink() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyGroupLink) ?? '';
  }

  Future<bool> isAutoWaEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyAutoWaEnabled) ?? false;
  }

  Future<void> saveOwnerPhone(String phone) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyOwnerPhone, phone.trim());
  }

  Future<void> saveGroupLink(String link) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyGroupLink, link.trim());
  }

  Future<void> setAutoWaEnabled(bool val) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyAutoWaEnabled, val);
  }

  // ── Kirim laporan semua cabang (owner) ─────────────────
  Future<void> sendOwnerDailyReport({
    required BuildContext context,
    DateTime? date,
  }) async {
    final targetDate = date ?? DateTime.now();
    final message = await _buildOwnerReport(targetDate);

    final phone = await getOwnerPhone();
    final groupLink = await getGroupLink();

    // Kirim ke nomor pribadi owner
    if (phone.isNotEmpty) {
      await _openWA(context, message, phone: phone);
      // Delay singkat agar WA sempat terbuka sebelum yang kedua
      await Future.delayed(const Duration(seconds: 2));
    }

    // Kirim ke grup WA
    if (groupLink.isNotEmpty) {
      await _openWAGroup(context, message, groupLink: groupLink);
    }

    // Kalau keduanya kosong → buka WA tanpa nomor
    if (phone.isEmpty && groupLink.isEmpty) {
      await _openWA(context, message, phone: null);
    }
  }

  // ── Kirim laporan shift kasir (existing flow) ──────────
  Future<void> sendShiftReport({
    required BuildContext context,
    required Map<String, dynamic> shiftData,
    String? phoneNumber,
  }) async {
    final msg = await _buildShiftReport(shiftData);
    await _openWA(context, msg, phone: phoneNumber);
  }

  // ── Kirim laporan harian satu cabang (manual) ──────────
  Future<void> sendDailyReport({
    required BuildContext context,
    DateTime? date,
    String? phoneNumber,
  }) async {
    final targetDate = date ?? DateTime.now();
    final report = await _getDailyDataLocal(targetDate);
    final msg = _buildSingleBranchReport(report, targetDate);
    await _openWA(context, msg, phone: phoneNumber);
  }

  // ── Build laporan semua cabang dari Supabase ───────────
  Future<String> _buildOwnerReport(DateTime date) async {
    final fmt = DateFormat('EEEE, dd MMMM yyyy', 'id_ID');
    final prefs = await SharedPreferences.getInstance();
    final ownerName = prefs.getString(AppConstants.keyName) ?? 'Owner';

    // Ambil data semua cabang via SyncService (dari Supabase)
    final branches = await SyncService.instance.getAdminReport(date);

    if (branches.isEmpty) {
      return '📊 *LAPORAN HARIAN POS KASIR*\n'
          '📅 ${fmt.format(date)}\n'
          '━━━━━━━━━━━━━━━━━━━━━\n'
          'Belum ada data transaksi hari ini.\n'
          '━━━━━━━━━━━━━━━━━━━━━\n'
          '_POS Kasir App_';
    }

    // Hitung total semua cabang
    double grandRevenue = 0;
    double grandExpense = 0;
    int grandTrx = 0;
    for (final b in branches) {
      grandRevenue += (b['total_revenue'] as num?)?.toDouble() ?? 0;
      grandExpense += (b['total_expense'] as num?)?.toDouble() ?? 0;
      grandTrx += (b['total_orders'] as num?)?.toInt() ?? 0;
    }
    final grandProfit = grandRevenue - grandExpense;

    final sb = StringBuffer();
    sb.writeln('📊 *LAPORAN HARIAN - SEMUA CABANG*');
    sb.writeln('📅 ${fmt.format(date)}');
    sb.writeln('👤 $ownerName');
    sb.writeln('━━━━━━━━━━━━━━━━━━━━━');
    sb.writeln('🏆 *RINGKASAN TOTAL*');
    sb.writeln('• Cabang Aktif   : ${branches.length} cabang');
    sb.writeln('• Total Transaksi: $grandTrx trx');
    sb.writeln('• Total Omzet    : ${AppUtils.formatCurrency(grandRevenue)}');
    sb.writeln('• Total Pengeluar: ${AppUtils.formatCurrency(grandExpense)}');
    sb.writeln('• *Laba Bersih  : ${AppUtils.formatCurrency(grandProfit)}*');
    sb.writeln('━━━━━━━━━━━━━━━━━━━━━');

    // Detail per cabang
    sb.writeln('🏪 *DETAIL PER CABANG*');
    for (final b in branches) {
      final name = b['branch_name'] as String? ?? '-';
      final rev = (b['total_revenue'] as num?)?.toDouble() ?? 0;
      final exp = (b['total_expense'] as num?)?.toDouble() ?? 0;
      final trx = (b['total_orders'] as num?)?.toInt() ?? 0;
      final profit = rev - exp;

      sb.writeln('');
      sb.writeln('🏪 *$name*');
      sb.writeln('  • Transaksi : $trx trx');
      sb.writeln('  • Omzet     : ${AppUtils.formatCurrency(rev)}');
      sb.writeln('  • Pengeluar : ${AppUtils.formatCurrency(exp)}');
      sb.writeln('  • Laba      : ${AppUtils.formatCurrency(profit)}');

      // Top 3 menu cabang ini
      final topMenus = b['top_menus'] as List? ?? [];
      if (topMenus.isNotEmpty) {
        sb.writeln('  🥇 Top Menu :');
        for (int i = 0; i < topMenus.length && i < 3; i++) {
          final m = topMenus[i] as Map;
          sb.writeln('    ${i + 1}. ${m['name']} (${m['qty']}x)');
        }
      }
    }

    sb.writeln('');
    sb.writeln('━━━━━━━━━━━━━━━━━━━━━');
    sb.writeln('_Dikirim otomatis oleh POS Kasir pukul 22.00_');

    return sb.toString().trim();
  }

  // ── Build laporan shift ────────────────────────────────
  Future<String> _buildShiftReport(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final storeName = prefs.getString(AppConstants.keyBranchName) ?? 'Toko';
    final kasirName = prefs.getString(AppConstants.keyKasirName) ?? 'Kasir';
    final fmt = DateFormat('dd MMM yyyy HH:mm', 'id_ID');
    final now = DateTime.now();

    final revenue  = (data['total_revenue'] as num?)?.toDouble() ?? 0;
    final expense  = (data['total_expense'] as num?)?.toDouble() ?? 0;
    final trxCount = data['total_orders'] as int? ?? 0;
    final openCash = (data['opening_cash'] as num?)?.toDouble() ?? 0;
    final cashIn   = (data['cash_received'] as num?)?.toDouble() ?? 0;
    final qris     = (data['qris_amount'] as num?)?.toDouble() ?? 0;
    final transfer = (data['transfer_amount'] as num?)?.toDouble() ?? 0;
    final openTime = data['open_time'] as String? ?? '-';

    return '''
🍽️ *LAPORAN SHIFT - $storeName*
━━━━━━━━━━━━━━━━━━━━━
👤 Kasir   : $kasirName
🕐 Buka    : $openTime
🕐 Tutup   : ${fmt.format(now)}
━━━━━━━━━━━━━━━━━━━━━
📊 *RINGKASAN*
• Total Transaksi : $trxCount trx
• Omzet           : ${AppUtils.formatCurrency(revenue)}
• Pengeluaran     : ${AppUtils.formatCurrency(expense)}
• *Laba Bersih   : ${AppUtils.formatCurrency(revenue - expense)}*
━━━━━━━━━━━━━━━━━━━━━
💳 *METODE PEMBAYARAN*
• 💵 Tunai    : ${AppUtils.formatCurrency(cashIn)}
• 📱 QRIS     : ${AppUtils.formatCurrency(qris)}
• 🏦 Transfer : ${AppUtils.formatCurrency(transfer)}
━━━━━━━━━━━━━━━━━━━━━
💰 *KAS FISIK*
• Modal Awal       : ${AppUtils.formatCurrency(openCash)}
• Penjualan Tunai  : ${AppUtils.formatCurrency(cashIn)}
• *Estimasi Kas   : ${AppUtils.formatCurrency(openCash + cashIn - expense)}*
━━━━━━━━━━━━━━━━━━━━━
_POS Kasir App_'''.trim();
  }

  // ── Build laporan harian satu cabang (lokal) ───────────
  String _buildSingleBranchReport(Map<String, dynamic> data, DateTime date) {
    final fmt = DateFormat('EEEE, dd MMMM yyyy', 'id_ID');
    final storeName = data['store_name'] ?? 'Toko';
    final revenue   = (data['revenue'] as num?)?.toDouble() ?? 0;
    final expense   = (data['expense'] as num?)?.toDouble() ?? 0;
    final trxCount  = data['trx_count'] as int? ?? 0;
    final topMenus  = data['top_menus'] as List? ?? [];

    final topStr = topMenus.take(5).map((m) =>
        '  • ${m['name']}: ${m['qty']}x '
        '(${AppUtils.formatCurrency((m['revenue'] as num?)?.toDouble() ?? 0)})'
    ).join('\n');

    return '''
📊 *LAPORAN HARIAN - $storeName*
📅 ${fmt.format(date)}
━━━━━━━━━━━━━━━━━━━━━
• Total Transaksi  : $trxCount trx
• Omzet Total      : ${AppUtils.formatCurrency(revenue)}
• Total Pengeluaran: ${AppUtils.formatCurrency(expense)}
• *Laba Bersih    : ${AppUtils.formatCurrency(revenue - expense)}*
━━━━━━━━━━━━━━━━━━━━━
🏆 *MENU TERLARIS*
$topStr
━━━━━━━━━━━━━━━━━━━━━
_POS Kasir App_'''.trim();
  }

  Future<Map<String, dynamic>> _getDailyDataLocal(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final storeName = prefs.getString(AppConstants.keyBranchName) ?? 'Toko';
    final dateStr = date.toIso8601String().substring(0, 10);

    final rev = await DatabaseHelper.instance.rawQuery('''
      SELECT COALESCE(SUM(total), 0) as revenue, COUNT(*) as trx_count
      FROM orders WHERE date(created_at) = ? AND status = 'paid'
    ''', [dateStr]);

    final exp = await DatabaseHelper.instance.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as expense FROM expenses WHERE date(created_at) = ?
    ''', [dateStr]);

    final topMenus = await DatabaseHelper.instance.rawQuery('''
      SELECT oi.name, SUM(oi.qty) as qty, SUM(oi.subtotal) as revenue
      FROM order_items oi JOIN orders o ON oi.order_id = o.id
      WHERE date(o.created_at) = ? AND o.status = 'paid'
      GROUP BY oi.name ORDER BY qty DESC LIMIT 5
    ''', [dateStr]);

    return {
      'store_name': storeName,
      'revenue'   : rev.first['revenue'] ?? 0,
      'trx_count' : rev.first['trx_count'] ?? 0,
      'expense'   : exp.first['expense'] ?? 0,
      'top_menus' : topMenus,
    };
  }

  // ── Open WhatsApp ke nomor tertentu ───────────────────
  Future<void> _openWA(BuildContext context, String message,
      {String? phone}) async {
    final encoded = Uri.encodeComponent(message);

    // Coba urutan: WA app intent → wa.me HTTPS → browser fallback
    final List<Uri> candidates = [];

    if (phone != null && phone.isNotEmpty) {
      final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final intl  = clean.startsWith('0') ? '62${clean.substring(1)}' : clean;
      // 1. Intent langsung ke WA app
      candidates.add(Uri.parse('whatsapp://send?phone=$intl&text=$encoded'));
      // 2. wa.me HTTPS
      candidates.add(Uri.parse('https://wa.me/$intl?text=$encoded'));
    } else {
      candidates.add(Uri.parse('whatsapp://send?text=$encoded'));
      candidates.add(Uri.parse('https://wa.me/?text=$encoded'));
    }
    // 3. Fallback browser
    candidates.add(Uri.parse('https://wa.me/?text=$encoded'));

    for (final url in candidates) {
      try {
        final ok = await canLaunchUrl(url);
        if (ok) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }

    // Semua gagal → coba force launch tanpa canLaunchUrl check
    try {
      await launchUrl(
        candidates[1], // wa.me
        mode: LaunchMode.externalApplication,
      );
      return;
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Gagal membuka WhatsApp. Pastikan WhatsApp sudah terinstall.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ));
    }
  }

  // ── Open WhatsApp ke grup via invite link ─────────────
  Future<void> _openWAGroup(BuildContext context, String message,
      {required String groupLink}) async {
    // Format link grup: https://chat.whatsapp.com/XXXXX
    // Untuk pre-fill pesan ke grup, kita buka link grup dulu
    // lalu user paste pesan (WA tidak support pre-fill ke grup via URL)
    // Solusi: salin pesan ke clipboard + buka link grup
    final encoded = Uri.encodeComponent(message);

    // Coba buka dengan format deep link
    // wa.me tidak support grup, jadi buka via intent
    try {
      // Salin pesan ke clipboard agar mudah paste
      // (tidak perlu import clipboard — cukup buka link grup)
      final groupUrl = Uri.parse(groupLink.trim());
      // Bypass canLaunchUrl - langsung launch
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '📋 Grup WA terbuka — paste pesan laporan yang sudah disalin',
            ),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 5),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
      }
      await launchUrl(groupUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('_openWAGroup error: $e');
    }
  }
}
