import '../utils/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/reports/data/services/pdf_service.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import '../database/database_helper.dart';
import '../utils/app_utils.dart';
import 'whatsapp_report_service.dart';

// Auto PDF runs when user opens app after 10 PM
// No background processing needed - runs on app resume

class AutoNotificationService {
  static Future<void> init() async {
    // No external notification package needed
  }

  static Future<void> showSnackbar(
      BuildContext context, String title, String body) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

class SimpleSettingsProvider extends SettingsProvider {
  final Map<String, String> _data;
  SimpleSettingsProvider(this._data);

  @override String get storeName => _data['store_name'] ?? 'Warung Makan';
  @override String get storeAddress => _data['store_address'] ?? '';
  @override String get storePhone => _data['store_phone'] ?? '';
  @override String get receiptHeader => _data['receipt_header'] ?? '';
  @override String get receiptFooter => _data['receipt_footer'] ?? '';
  @override bool get taxEnabled => _data['tax_enabled'] == '1';
  @override double get taxPercent =>
      double.tryParse(_data['tax_percent'] ?? '0') ?? 0;
  @override bool get isDarkMode => false;
  @override String get receiptWidth => _data['receipt_width'] ?? '58';
  @override String get currencySymbol => _data['currency_symbol'] ?? 'Rp';
  @override String? get logoPath => null;
  @override bool get loaded => true;
}

class SchedulerService {
  // Check if auto PDF should run (called on app open/resume)
  static Future<bool> shouldRunAutoPdf() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('auto_pdf_enabled') ?? false;
    if (!enabled) return false;

    // BUG 53 FIX: Hanya owner/superadmin yang kirim laporan PDF otomatis.
    // Sebelumnya semua device (kasir pun) bisa trigger auto PDF setelah jam 22.
    final role = prefs.getString(AppConstants.keyRole) ?? '';
    if (role != 'owner' && role != 'superadmin') return false;

    final now = DateTime.now();
    // Run if it's after 10 PM
    if (now.hour < 22) return false;

    // Check if already ran today
    final lastRun = prefs.getString('auto_pdf_last_run') ?? '';
    final today = now.toIso8601String().substring(0, 10);
    if (lastRun == today) return false;

    return true;
  }

  static Future<void> runAutoPdf(BuildContext context) async {
    try {
      final db = DatabaseHelper.instance;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      final settingsRows =
          await db.rawQuery('SELECT key, value FROM settings');
      final settingsMap = {
        for (var r in settingsRows)
          r['key'] as String: r['value'] as String? ?? ''
      };

      final summary = await db.rawQuery('''
        SELECT COUNT(*) as total_orders,
               COALESCE(SUM(total),0) as total_revenue,
               COALESCE(AVG(total),0) as avg_transaction
        FROM orders WHERE status='paid' AND DATE(created_at)=?
      ''', [today]);

      final expenses = await db.rawQuery('''
        SELECT COALESCE(SUM(amount),0) as total
        FROM expenses WHERE date=?
      ''', [today]);

      final topMenus = await db.rawQuery('''
        SELECT oi.name, SUM(oi.qty) as total_qty,
               SUM(oi.subtotal) as total_revenue
        FROM order_items oi
        JOIN orders o ON oi.order_id=o.id
        WHERE o.status='paid' AND DATE(o.created_at)=?
        GROUP BY oi.name ORDER BY total_qty DESC LIMIT 10
      ''', [today]);

      final totalRevenue =
          (summary.first['total_revenue'] as num?)?.toDouble() ?? 0;
      final totalTransactions = (summary.first['total_orders'] as int?) ?? 0;
      final avgTransaction =
          (summary.first['avg_transaction'] as num?)?.toDouble() ?? 0;
      final totalExpenses =
          (expenses.first['total'] as num?)?.toDouble() ?? 0;

      final simpleSettings = SimpleSettingsProvider(settingsMap);

      await PdfService.exportDailyReport(
        date: DateTime.now(),
        totalRevenue: totalRevenue,
        totalTransactions: totalTransactions,
        avgTransaction: avgTransaction,
        topMenus: topMenus,
        paymentBreakdown: [],
        totalExpenses: totalExpenses,
        settings: simpleSettings,
      );

      // Mark as done today
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auto_pdf_last_run', today);

      if (context.mounted) {
        await AutoNotificationService.showSnackbar(
          context,
          '📊 Laporan PDF Terkirim!',
          'Omset: ${AppUtils.formatCurrency(totalRevenue)} • '
              'Laba: ${AppUtils.formatCurrency(totalRevenue - totalExpenses)}',
        );
      }
    } catch (e) {
      debugPrint('Auto PDF error: $e');
    }
  }

  static Future<void> setupAutoPdf(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_pdf_enabled', enabled);
    await DatabaseHelper.instance.insert('settings', {
      'key': 'auto_pdf_enabled',
      'value': enabled ? '1' : '0',
    });
  }

  static Future<bool> isAutoPdfEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('auto_pdf_enabled') ?? false;
  }

  // ── Auto WA laporan semua cabang jam 22:00 ────────────
  static Future<bool> shouldRunAutoWa() async {
    final prefs = await SharedPreferences.getInstance();

    // Cek apakah fitur aktif
    final enabled = await WhatsAppReportService.instance.isAutoWaEnabled();
    if (!enabled) return false;

    // Hanya owner/superadmin yang kirim laporan semua cabang
    final role = prefs.getString(AppConstants.keyRole) ?? '';
    if (role != 'owner' && role != 'superadmin') return false;

    // Hanya jam 22:00 ke atas
    final now = DateTime.now();
    if (now.hour < 22) return false;

    // Cek apakah sudah jalan hari ini
    final lastRun = prefs.getString('auto_wa_last_run') ?? '';
    final today = now.toIso8601String().substring(0, 10);
    if (lastRun == today) return false;

    return true;
  }

  static Future<void> runAutoWa(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // Tandai sudah jalan hari ini dulu agar tidak double
      await prefs.setString('auto_wa_last_run', today);

      if (!context.mounted) return;

      // Tampilkan snackbar info sebelum buka WA
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('📊 Membuat laporan semua cabang untuk WA...'),
          backgroundColor: Colors.blue[700],
          duration: const Duration(seconds: 3),
        ),
      );

      await Future.delayed(const Duration(seconds: 1));
      if (!context.mounted) return;

      await WhatsAppReportService.instance.sendOwnerDailyReport(
        context: context,
        date: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Auto WA error: $e');
    }
  }

  static Future<void> setupAutoWa(bool enabled) async {
    await WhatsAppReportService.instance.setAutoWaEnabled(enabled);
  }
}
