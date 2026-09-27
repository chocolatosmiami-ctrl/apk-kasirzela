import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../orders/data/models/order_models.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/utils/app_utils.dart';

class PdfService {
  static String _fmtQty(num q) => q == q.toInt() ? q.toInt().toString() : q.toString();
  static String _fmtQtyUnit(num q, String? unit) {
    final qs = _fmtQty(q);
    if (unit != null && unit.isNotEmpty) return qs + ' ' + unit;
    return qs + 'x';
  }

  // ── Laporan Harian PDF ────────────────────────────────
  static Future<void> exportDailyReport({
    required DateTime date,
    required double totalRevenue,
    required int totalTransactions,
    required double avgTransaction,
    required List<Map<String, dynamic>> topMenus,
    required List<Map<String, dynamic>> paymentBreakdown,
    required double totalExpenses,
    required SettingsProvider settings,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(settings.storeName,
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.Text('Laporan Penjualan Harian',
                    style: const pw.TextStyle(fontSize: 14)),
                pw.Text(
                    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                    style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Ringkasan',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _pdfRow('Total Pendapatan', AppUtils.formatCurrency(totalRevenue), bold: true),
          _pdfRow('Total Transaksi', totalTransactions.toString()),
          _pdfRow('Rata-rata Transaksi', AppUtils.formatCurrency(avgTransaction)),
          _pdfRow('Total Pengeluaran', AppUtils.formatCurrency(totalExpenses), color: PdfColors.red),
          _pdfRow('Laba Bersih', AppUtils.formatCurrency(totalRevenue - totalExpenses),
              bold: true, color: PdfColors.green700),
          pw.Divider(),
          if (topMenus.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Menu Terlaris',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            ...topMenus.map((m) => _pdfRow(
              m['name'] as String? ?? '-',
              '${m['total_qty']} terjual',
            )),
          ],
          if (paymentBreakdown.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Metode Pembayaran',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            ...paymentBreakdown.map((p) => _pdfRow(
              p['method'] as String? ?? '-',
              AppUtils.formatCurrency((p['total'] as num?)?.toDouble() ?? 0),
            )),
          ],
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/laporan_${date.year}${date.month.toString().padLeft(2,'0')}${date.day.toString().padLeft(2,'0')}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Laporan Harian ${settings.storeName}',
    );
  }

  // ── Share Struk Customer sebagai PDF ─────────────────
  static Future<void> shareReceipt(
      OrderModel order, SettingsProvider settings) async {
    try {
      final pdfBytes = await _generateReceiptPdf(order, settings);
      final dir = await getTemporaryDirectory();
      final safeName = order.orderNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final file = File('${dir.path}/struk_$safeName.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Struk ${settings.storeName}',
        text: '${settings.storeName} - ${order.orderNumber}',
      );
    } catch (e) {
      // Fallback: share teks biasa
      final sb = StringBuffer();
      sb.writeln(settings.storeName);
      if (settings.storeAddress.isNotEmpty) sb.writeln(settings.storeAddress);
      sb.writeln('================================');
      sb.writeln('No: ${order.orderNumber}');
      try { sb.writeln(AppUtils.formatDateTime(AppUtils.safeParseDate(order.createdAt))); } catch (_) {}
      if (order.cashierName != null && order.cashierName!.isNotEmpty)
        sb.writeln('Kasir: ${order.cashierName}');
      sb.writeln('--------------------------------');
      for (final item in order.items) {
        sb.writeln('${_fmtQtyUnit(item.qty, item.unit)} ${item.name}');
        sb.writeln('   ${AppUtils.formatCurrency(item.subtotal)}');
      }
      sb.writeln('================================');
      if (order.discountAmount > 0) {
        sb.writeln('Subtotal : ${AppUtils.formatCurrency(order.subtotal)}');
        sb.writeln('Diskon   : -${AppUtils.formatCurrency(order.discountAmount)}');
      }
      if (order.taxAmount > 0)
        sb.writeln('Pajak    : \${AppUtils.formatCurrency(order.taxAmount)}');
      if (order.serviceChargeAmount > 0)
        sb.writeln('Servis   : \${AppUtils.formatCurrency(order.serviceChargeAmount)}');
      sb.writeln('TOTAL    : \${AppUtils.formatCurrency(order.total)}');
      sb.writeln('Bayar    : \${AppUtils.getPaymentMethodLabel(order.paymentMethod ?? '')}');
      if (order.paymentMethod == 'cash') {
        sb.writeln('Terima   : ${AppUtils.formatCurrency(order.paidAmount)}');
        sb.writeln('Kembali  : ${AppUtils.formatCurrency(order.changeAmount)}');
      }
      if (settings.receiptFooter.isNotEmpty) sb.writeln(settings.receiptFooter);
      sb.writeln('Terima kasih!');
      await Share.share(sb.toString(), subject: 'Struk ${settings.storeName}');
    }
  }

  // ── Print langsung ke printer ─────────────────────────
  static Future<void> printReceipt(
      OrderModel order, SettingsProvider settings) async {
    final pdfBytes = await _generateReceiptPdf(order, settings);
    await Printing.layoutPdf(
      onLayout: (_) async => pdfBytes,
      name: 'Struk ${order.orderNumber}',
    );
  }

  // ── Generate PDF thermal 58mm ─────────────────────────
  static Future<Uint8List> _generateReceiptPdf(
      OrderModel order, SettingsProvider settings) async {
    final pdf = pw.Document();
    DateTime? now;
    try { now = AppUtils.safeParseDate(order.createdAt); } catch (_) { now = DateTime.now(); }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          58 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // ── Header toko ──────────────────────────
            pw.Text(
              settings.storeName,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            if (settings.storeAddress.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(settings.storeAddress,
                  style: const pw.TextStyle(fontSize: 7),
                  textAlign: pw.TextAlign.center),
            ],
            if (settings.storePhone.isNotEmpty)
              pw.Text('Telp: ${settings.storePhone}',
                  style: const pw.TextStyle(fontSize: 7),
                  textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 3),
            pw.Divider(thickness: 0.5),

            // ── Info transaksi ────────────────────────
            _row8('No', order.orderNumber.length > 12
                ? order.orderNumber.substring(order.orderNumber.length - 12)
                : order.orderNumber),
            _row8('Tgl',
              '${now!.day.toString().padLeft(2,'0')}'
                  '/${now.month.toString().padLeft(2,'0')}'
                  '/${now.year} '
                  '${now.hour.toString().padLeft(2,'0')}'
                  ':${now.minute.toString().padLeft(2,'0')}',
            ),
            if (order.tableNumber != null && order.tableNumber!.isNotEmpty)
              _row8('Meja', order.tableNumber!),
            if (order.cashierName != null && order.cashierName!.isNotEmpty)
              _row8('Kasir', order.cashierName!),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 2),

            // ── Items ─────────────────────────────────
            ...order.items.map((item) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${_fmtQtyUnit(item.qty, item.unit)} ${item.name}',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '  @${AppUtils.formatCurrency(item.price)}',
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                      pw.Text(
                        AppUtils.formatCurrency(item.subtotal),
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            )),

            pw.Divider(thickness: 0.5),

            // ── Summary ───────────────────────────────
            if (order.discountAmount > 0) ...[
              _row8('Subtotal', AppUtils.formatCurrency(order.subtotal)),
              _row8('Diskon', '-${AppUtils.formatCurrency(order.discountAmount)}'),
            ],
            if (order.taxAmount > 0)
              _row8('Pajak', AppUtils.formatCurrency(order.taxAmount)),
            if (order.serviceChargeAmount > 0)
              _row8('Servis', AppUtils.formatCurrency(order.serviceChargeAmount)),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text(AppUtils.formatCurrency(order.total),
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.Divider(thickness: 0.5),

            // ── Pembayaran ────────────────────────────
            _row8('Bayar', AppUtils.getPaymentMethodLabel(order.paymentMethod ?? '')),
            if (order.paymentMethod == 'cash') ...[
              _row8('Terima', AppUtils.formatCurrency(order.paidAmount)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Kembali',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(AppUtils.formatCurrency(order.changeAmount),
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
            pw.SizedBox(height: 5),

            if (settings.receiptFooter.isNotEmpty) ...[
              pw.Divider(thickness: 0.3),
              pw.Text(settings.receiptFooter,
                  style: const pw.TextStyle(fontSize: 7),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 3),
            ],
            pw.Text(
              '*** Terima Kasih ***',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 8),
          ],
        ),
      ),
    );

    return Uint8List.fromList(await pdf.save());
  }

  // ── Helper widgets ────────────────────────────────────
  static pw.Widget _row8(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 1),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
      ],
    ),
  );

  static pw.Widget _pdfRow(String label, String value,
      {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: color ?? PdfColors.black)),
        ],
      ),
    );
  }

  static pw.Widget _tableHeader(String text) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(text,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
  );

  static pw.Widget _tableCell(String text) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(text, style: const pw.TextStyle(fontSize: 10)),
  );
}