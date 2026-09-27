import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../orders/data/models/order_models.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/utils/app_utils.dart';

class PrinterDevice {
  final String name;
  final String address;
  const PrinterDevice({required this.name, required this.address});
}

enum PrintResult { success, noDevice, connectFailed, printFailed }

class PrinterService {
  static final PrinterService instance = PrinterService._();
  PrinterService._();

  static const String _keyPrinterName    = 'bt_printer_name';
  static const String _keyPrinterAddress = 'bt_printer_address';
  static const String _keyPaperWidth     = 'bt_printer_width';

  // ── Simpan & load printer ─────────────────────────────
  Future<void> savePrinter(PrinterDevice device) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyPrinterName, device.name);
    await p.setString(_keyPrinterAddress, device.address);
  }

  Future<PrinterDevice?> getSavedPrinter() async {
    final p = await SharedPreferences.getInstance();
    final name    = p.getString(_keyPrinterName) ?? '';
    final address = p.getString(_keyPrinterAddress) ?? '';
    if (name.isEmpty || address.isEmpty) return null;
    return PrinterDevice(name: name, address: address);
  }

  Future<void> savePaperWidth(String width) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyPaperWidth, width);
  }

  Future<String> getPaperWidth() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyPaperWidth) ?? '58';
  }

  // ── Request permissions ───────────────────────────────
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;
    debugPrint('🖨️ [BT-PERM] Checking permissions...');

    try {
      // Helper: cek apakah status = granted ATAU limited
      bool isOk(PermissionStatus s) =>
          s == PermissionStatus.granted || s == PermissionStatus.limited;

      // BLUETOOTH_CONNECT
      var connectStatus = await Permission.bluetoothConnect.status;
      debugPrint('🖨️ [BT-PERM] bluetoothConnect: ${connectStatus.name}');
      if (!isOk(connectStatus) && !connectStatus.isPermanentlyDenied) {
        connectStatus = await Permission.bluetoothConnect.request();
        debugPrint('🖨️ [BT-PERM] after request: ${connectStatus.name}');
      }
      if (connectStatus.isPermanentlyDenied) {
        debugPrint('🖨️ [BT-PERM] permanently denied → open settings');
        await openAppSettings();
        return false;
      }

      // BLUETOOTH_SCAN
      var scanStatus = await Permission.bluetoothScan.status;
      if (!isOk(scanStatus) && !scanStatus.isPermanentlyDenied) {
        scanStatus = await Permission.bluetoothScan.request();
      }

      // Location - opsional
      try {
        var locStatus = await Permission.location.status;
        if (!isOk(locStatus) && !locStatus.isPermanentlyDenied) {
          await Permission.location.request();
        }
      } catch (_) {}

      // Kalau BLUETOOTH_CONNECT sudah ok (granted/limited) → lanjut
      final ok = isOk(connectStatus);
      debugPrint('🖨️ [BT-PERM] Final ok=$ok (${connectStatus.name})');
      return ok;
    } catch (e) {
      debugPrint('🖨️ [BT-PERM] error: $e');
      // Kalau error → coba tetap lanjut (mungkin permission sudah ada)
      return true;
    }
  }

  // ── Scan perangkat paired ─────────────────────────────
  Future<List<PrinterDevice>> getPairedDevices() async {
    try {
      await requestPermissions();
      final bool btEnabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!btEnabled) {
        debugPrint('🖨️ [BT] Bluetooth tidak aktif');
        return [];
      }
      final List<BluetoothInfo> devices =
      await PrintBluetoothThermal.pairedBluetooths;
      return devices
          .map((d) => PrinterDevice(name: d.name, address: d.macAdress))
          .toList();
    } catch (e) {
      debugPrint('🖨️ [BT] getPairedDevices error: $e');
      return [];
    }
  }

  // ── Connect ───────────────────────────────────────────
  Future<bool> connect(PrinterDevice device) async {
    try {
      // Disconnect dulu jika masih ada koneksi
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (connected) await PrintBluetoothThermal.disconnect;

      debugPrint('🖨️ [BT] Connecting to ${device.name} (${device.address})...');
      final result = await PrintBluetoothThermal.connect(
          macPrinterAddress: device.address);
      debugPrint('🖨️ [BT] connect result: $result');
      return result;
    } catch (e) {
      debugPrint('🖨️ [BT] connect error: $e');
      return false;
    }
  }

  // ── Disconnect ────────────────────────────────────────
  Future<void> disconnect() async {
    try { await PrintBluetoothThermal.disconnect; } catch (_) {}
  }

  Future<bool> isConnected() async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  // ── Helpers build ticket ──────────────────────────────
  List<int> _encode(String text) => text.codeUnits;

  // ESC/POS commands
  static const List<int> _esc    = [0x1B];
  static const List<int> _reset  = [0x1B, 0x40];          // ESC @  reset
  static const List<int> _bold1  = [0x1B, 0x45, 0x01];    // bold on
  static const List<int> _bold0  = [0x1B, 0x45, 0x00];    // bold off
  static const List<int> _center = [0x1B, 0x61, 0x01];    // align center
  static const List<int> _left   = [0x1B, 0x61, 0x00];    // align left
  static const List<int> _size2  = [0x1B, 0x21, 0x30];    // double width+height
  static const List<int> _size1  = [0x1B, 0x21, 0x00];    // normal size
  static const List<int> _lf     = [0x0A];                 // line feed
  static const List<int> _cut    = [0x1D, 0x56, 0x41, 0x10]; // cut paper

  // Convert logo URL ke ESC/POS bitmap menggunakan esc_pos_utils_plus
  static Future<List<int>?> _fetchAndConvertLogo(String url, int lineWidth) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      img.Image? decoded = img.decodeImage(response.bodyBytes);
      if (decoded == null) return null;

      // Resize ke max 200px lebar
      final targetWidth = math.min(200, lineWidth * 6);
      decoded = img.copyResize(decoded,
        width: targetWidth,
        height: (targetWidth * decoded.height / decoded.width).round(),
      );

      // Pakai generator dari esc_pos_utils_plus
      final profile = await CapabilityProfile.load();
      final generator = Generator(
        lineWidth == 32 ? PaperSize.mm58 : PaperSize.mm80,
        profile,
      );

      final List<int> bytes = [];
      bytes.addAll(generator.image(decoded, align: PosAlign.center));
      return bytes;
    } catch (e) {
      debugPrint('🖨️ [LOGO] error: ' + e.toString());
      return null;
    }
  }


  List<int> _line(String text,
      {bool bold = false, bool center = false, bool big = false}) {
    final List<int> b = [];
    if (center) b.addAll(_center); else b.addAll(_left);
    if (big) b.addAll(_size2);
    if (bold) b.addAll(_bold1);
    b.addAll(_encode(text));
    if (bold) b.addAll(_bold0);
    if (big) b.addAll(_size1);
    b.addAll(_lf);
    return b;
  }

  List<int> _row(String left, String right, {int totalWidth = 32}) {
    final space = totalWidth - left.length - right.length;
    final gap = space > 0 ? ' ' * space : ' ';
    return _line('$left$gap$right');
  }

  List<int> _divider({int width = 32}) =>
      _line('-' * width);

  // ── Print struk ───────────────────────────────────────
  Future<PrintResult> printReceipt(
      OrderModel order, SettingsProvider settings) async {
    if (!await isConnected()) {
      final saved = await getSavedPrinter();
      if (saved == null) return PrintResult.noDevice;
      final ok = await connect(saved);
      if (!ok) return PrintResult.connectFailed;
    }

    try {
      final width = await getPaperWidth();
      final lineWidth = width == '80' ? 42 : 32;

      final List<int> ticket = [];
      ticket.addAll(_reset);

      // ── Header ──────────────────────────────────────
      debugPrint('🖨️ [BT] storeName=' + settings.storeName + ' addr=' + settings.storeAddress);

      // Logo dari Supabase
      if (settings.logoUrl.isNotEmpty) {
        try {
          final logoBytes = await _fetchAndConvertLogo(settings.logoUrl, lineWidth);
          if (logoBytes != null && logoBytes.isNotEmpty) {
            ticket.addAll(logoBytes);
            debugPrint('🖨️ [BT] logo printed OK');
          }
        } catch (e) {
          debugPrint('🖨️ [BT] logo error: ' + e.toString());
        }
      }
      ticket.addAll(_line(settings.storeName, bold: true, center: true, big: true));
      if (settings.storeAddress.isNotEmpty)
        ticket.addAll(_line(settings.storeAddress, center: true));
      if (settings.storePhone.isNotEmpty)
        ticket.addAll(_line('Telp: ${settings.storePhone}', center: true));
      if (settings.receiptHeader.isNotEmpty)
        ticket.addAll(_line(settings.receiptHeader, center: true));

      ticket.addAll(_divider(width: lineWidth));

      // ── Info transaksi ───────────────────────────────
      final orderNum = order.orderNumber.length > 12
          ? order.orderNumber.substring(order.orderNumber.length - 12)
          : order.orderNumber;
      ticket.addAll(_row('No', orderNum, totalWidth: lineWidth));
      ticket.addAll(_row('Tgl',
          AppUtils.formatDateTime(AppUtils.safeParseDate(order.createdAt)),
          totalWidth: lineWidth));
      ticket.addAll(_row('Tipe',
          AppUtils.getOrderTypeLabel(order.orderType),
          totalWidth: lineWidth));
      if (order.tableNumber != null && order.tableNumber!.isNotEmpty)
        ticket.addAll(_row('Meja', 'Meja ${order.tableNumber}',
            totalWidth: lineWidth));
      if (order.cashierName != null && order.cashierName!.isNotEmpty)
        ticket.addAll(_row('Kasir', order.cashierName!, totalWidth: lineWidth));

      ticket.addAll(_divider(width: lineWidth));

      // ── Items ────────────────────────────────────────
      for (final item in order.items) {
        ticket.addAll(_line('${item.qty}x ${item.name}', bold: true));
        if (item.note != null && item.note!.isNotEmpty)
          ticket.addAll(_line('   * ${item.note}'));
        ticket.addAll(_row(
            '   @${AppUtils.formatCurrency(item.price)}',
            AppUtils.formatCurrency(item.subtotal),
            totalWidth: lineWidth));
      }

      ticket.addAll(_divider(width: lineWidth));

      // ── Summary ──────────────────────────────────────
      if (order.discountAmount > 0) {
        ticket.addAll(_row('Subtotal',
            AppUtils.formatCurrency(order.subtotal), totalWidth: lineWidth));
        ticket.addAll(_row('Diskon',
            '-${AppUtils.formatCurrency(order.discountAmount)}',
            totalWidth: lineWidth));
      }
      if (order.taxAmount > 0)
        ticket.addAll(_row('Pajak ${order.taxPercent.toInt()}%',
            AppUtils.formatCurrency(order.taxAmount), totalWidth: lineWidth));
      if (settings.serviceChargeEnabled && settings.serviceChargeAmount > 0)
        ticket.addAll(_row('Service',
            AppUtils.formatCurrency(settings.serviceChargeAmount),
            totalWidth: lineWidth));

      ticket.addAll(_line('=' * lineWidth));
      ticket.addAll(_line(
          _rowStr('TOTAL', AppUtils.formatCurrency(order.total),
              totalWidth: lineWidth),
          bold: true));
      ticket.addAll(_line('=' * lineWidth));

      // ── Pembayaran ───────────────────────────────────
      ticket.addAll(_row('Bayar',
          AppUtils.getPaymentMethodLabel(order.paymentMethod ?? ''),
          totalWidth: lineWidth));
      if (order.paymentMethod == 'cash') {
        ticket.addAll(_row('Terima',
            AppUtils.formatCurrency(order.paidAmount), totalWidth: lineWidth));
        ticket.addAll(_row('Kembali',
            AppUtils.formatCurrency(order.changeAmount),
            totalWidth: lineWidth));
      }

      // ── Footer ───────────────────────────────────────
      if (settings.receiptFooter.isNotEmpty) {
        ticket.addAll(_divider(width: lineWidth));
        ticket.addAll(_line(settings.receiptFooter, center: true));
      }
      ticket.addAll(_divider(width: lineWidth));
      ticket.addAll(_line('powered by kasirzela.id', center: true));
      ticket.addAll(_line('*** Terima Kasih ***', bold: true, center: true));
      ticket.addAll(_lf);
      ticket.addAll(_lf);
      ticket.addAll(_lf);
      ticket.addAll(_cut);

      final bool result =
      await PrintBluetoothThermal.writeBytes(ticket);
      debugPrint('🖨️ [BT] writeBytes result: $result');
      return result ? PrintResult.success : PrintResult.printFailed;
    } catch (e) {
      debugPrint('🖨️ [BT] printReceipt error: $e');
      return PrintResult.printFailed;
    }
  }

  // ── Test print ────────────────────────────────────────
  Future<PrintResult> printTestPage() async {
    if (!await isConnected()) {
      final saved = await getSavedPrinter();
      if (saved == null) return PrintResult.noDevice;
      final ok = await connect(saved);
      if (!ok) return PrintResult.connectFailed;
    }

    try {
      final width = await getPaperWidth();
      final lineWidth = width == '80' ? 42 : 32;
      final List<int> ticket = [];

      ticket.addAll(_reset);
      ticket.addAll(_line('TEST PRINT', bold: true, center: true, big: true));
      ticket.addAll(_line('POS Kasir App', center: true));
      ticket.addAll(_divider(width: lineWidth));
      ticket.addAll(_line('Printer terhubung!', center: true));
      ticket.addAll(_line('Lebar kertas: ${width}mm', center: true));
      ticket.addAll(_divider(width: lineWidth));
      ticket.addAll(_line('*** OK ***', bold: true, center: true));
      ticket.addAll(_lf);
      ticket.addAll(_lf);
      ticket.addAll(_lf);
      ticket.addAll(_cut);

      final bool result = await PrintBluetoothThermal.writeBytes(ticket);
      return result ? PrintResult.success : PrintResult.printFailed;
    } catch (e) {
      debugPrint('🖨️ [BT] testPage error: $e');
      return PrintResult.printFailed;
    }
  }

  // Helper string row
  String _rowStr(String left, String right, {int totalWidth = 32}) {
    final space = totalWidth - left.length - right.length;
    final gap = space > 0 ? ' ' * space : ' ';
    return '$left$gap$right';
  }

  // ── Build teks struk (fallback share) ─────────────────
  String buildReceiptText(OrderModel order, SettingsProvider settings) {
    final sb = StringBuffer();
    sb.writeln(settings.storeName);
    if (settings.storeAddress.isNotEmpty) sb.writeln(settings.storeAddress);
    if (settings.storePhone.isNotEmpty) sb.writeln('Telp: ${settings.storePhone}');
    sb.writeln('--------------------------------');
    sb.writeln('No: ${order.orderNumber}');
    sb.writeln('Tgl: ${AppUtils.formatDateTime(AppUtils.safeParseDate(order.createdAt))}');
    if (order.cashierName != null && order.cashierName!.isNotEmpty)
      sb.writeln('Kasir: ${order.cashierName}');
    sb.writeln('--------------------------------');
    for (final item in order.items) {
      sb.writeln('${item.qty}x ${item.name}');
      sb.writeln('   ${AppUtils.formatCurrency(item.price)} = ${AppUtils.formatCurrency(item.subtotal)}');
      if (item.note != null && item.note!.isNotEmpty)
        sb.writeln('   *${item.note}');
    }
    sb.writeln('--------------------------------');
    if (order.discountAmount > 0) {
      sb.writeln('Subtotal: ${AppUtils.formatCurrency(order.subtotal)}');
      sb.writeln('Diskon  : -${AppUtils.formatCurrency(order.discountAmount)}');
    }
    if (order.taxAmount > 0)
      sb.writeln('Pajak ${order.taxPercent.toInt()}%: ${AppUtils.formatCurrency(order.taxAmount)}');
    sb.writeln('================================');
    sb.writeln('TOTAL: ${AppUtils.formatCurrency(order.total)}');
    sb.writeln('================================');
    sb.writeln('Bayar: ${AppUtils.getPaymentMethodLabel(order.paymentMethod ?? '')}');
    if (order.paymentMethod == 'cash') {
      sb.writeln('Terima : ${AppUtils.formatCurrency(order.paidAmount)}');
      sb.writeln('Kembali: ${AppUtils.formatCurrency(order.changeAmount)}');
    }
    if (settings.receiptFooter.isNotEmpty) sb.writeln(settings.receiptFooter);
    sb.writeln('Terima kasih!');
    return sb.toString();
  }
}