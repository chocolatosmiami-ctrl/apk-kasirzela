import 'package:intl/intl.dart';

class AppUtils {
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static String formatCurrency(double amount) {
    try {
      return _currencyFormat.format(amount);
    } catch (_) {
      return 'Rp ${amount.toStringAsFixed(0)}';
    }
  }

  static String formatDate(DateTime date) {
    try {
      return DateFormat('dd MMM yyyy', 'id_ID').format(date);
    } catch (_) {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }

  static String formatDateTime(DateTime date) {
    try {
      return DateFormat('dd MMM yyyy HH:mm', 'id_ID').format(date);
    } catch (_) {
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    }
  }

  static String formatTime(DateTime date) {
    try {
      return DateFormat('HH:mm').format(date);
    } catch (_) {
      return '${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}';
    }
  }

  static String generateOrderNumber() {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(now);
    final timeStr = DateFormat('HHmmss').format(now);
    // BUG 18 FIX: Tambahkan microsecond + random 3 digit agar unik
    // meski 2 kasir checkout dalam 1 detik yang sama.
    final micro = (now.microsecond ~/ 1000).toString().padLeft(3, '0');
    final rand  = (DateTime.now().microsecondsSinceEpoch % 900 + 100).toString();
    return 'ORD-$dateStr-$timeStr-$micro$rand';
  }

  static String getOrderTypeLabel(String type) {
    switch (type) {
      case 'dine_in': return 'Makan di Sini';
      case 'takeaway': return 'Bawa Pulang';
      case 'delivery': return 'Antar';
      default: return 'Makan di Sini';
    }
  }

  static String getStatusLabel(String status) {
    switch (status) {
      case 'new': return 'Baru';
      case 'processing': return 'Diproses';
      case 'done': return 'Selesai';
      case 'paid': return 'Dibayar';
      case 'cancelled': return 'Dibatal';
      default: return status;
    }
  }

  static String getPaymentMethodLabel(String method) {
    switch (method) {
      case 'cash': return 'Tunai';
      case 'qris': return 'QRIS';
      case 'transfer': return 'Transfer';
      case 'card': return 'Kartu';
      default: return method;
    }
  }

  static String getRoleLabel(String role) {
    switch (role) {
      case 'admin': return 'Admin';
      case 'manajer': return 'Manajer';
      case 'kasir': return 'Kasir';
      default: return role;
    }
  }


  // Safe date parser - handles Supabase timezone format (+00:00, Z, etc)
  static DateTime safeParseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return DateTime.now();
    try {
      // toLocal() untuk konversi UTC -> WIB (UTC+7)
      return DateTime.parse(dateStr).toLocal();
    } catch (_) {
      try {
        var clean = dateStr;
        if (clean.contains('+') && clean.lastIndexOf('+') > 10) {
          clean = clean.substring(0, clean.lastIndexOf('+'));
        }
        clean = clean.replaceAll('Z', '').trim();
        // Parse sebagai UTC lalu convert ke local
        return DateTime.parse(clean + 'Z').toLocal();
      } catch (_) {
        return DateTime.now();
      }
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

}