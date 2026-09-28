import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/utils/app_constants.dart';
import '../../data/models/printer_station_model.dart';

class PrinterStationProvider extends ChangeNotifier {
  List<PrinterStationModel> _stations = [];
  bool _isLoading = false;
  String? _error;

  List<PrinterStationModel> get stations => _stations;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<PrinterStationModel> get kasirStations =>
      _stations.where((s) => s.stationType == 'kasir').toList();
  List<PrinterStationModel> get dapurStations =>
      _stations.where((s) => s.stationType == 'dapur').toList();
  List<PrinterStationModel> get checkerStations =>
      _stations.where((s) => s.stationType == 'checker').toList();

  Future<void> loadStations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final prefs    = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      if (branchId.isEmpty) {
        _stations = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      final result = await SupabaseConfig.client
          .rpc('get_printer_stations', params: {'p_branch_id': branchId});

      final list = (result as List<dynamic>? ?? []);
      _stations = list
          .map((e) => PrinterStationModel.fromMap(e as Map<String, dynamic>))
          .toList();
      debugPrint('🖨️ [PRINTER-STATION] Loaded ${_stations.length} stations');
    } catch (e) {
      _error = e.toString();
      debugPrint('🖨️ [PRINTER-STATION] Error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> saveStation(PrinterStationModel station) async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';

      final result = await SupabaseConfig.client.rpc('upsert_printer_station', params: {
        'p_branch_id':       station.branchId,
        'p_owner_id':        ownerId,
        'p_name':            station.name,
        'p_station_type':    station.stationType,
        'p_printer_name':    station.printerName,
        'p_printer_address': station.printerAddress,
        'p_paper_width':     station.paperWidth,
        'p_auto_print':      station.autoPrint,
        if (station.id != null) 'p_station_id': station.id,
      });

      final success = result?['success'] as bool? ?? false;
      if (success) {
        final newId = result?['id']?.toString();

        if (newId != null && station.menuItems.isNotEmpty) {
          await SupabaseConfig.client
              .from('printer_station_menus')
              .delete()
              .eq('station_id', newId);

          final menuRows = station.menuItems
              .map((m) => {'station_id': newId, 'menu_item_name': m})
              .toList();
          await SupabaseConfig.client
              .from('printer_station_menus')
              .insert(menuRows);
        } else if (newId != null && station.menuItems.isEmpty) {
          // Hapus semua menu filter jika dikosongkan
          await SupabaseConfig.client
              .from('printer_station_menus')
              .delete()
              .eq('station_id', newId);
        }

        await loadStations();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('🖨️ [PRINTER-STATION] Save error: $e');
      return false;
    }
  }

  Future<bool> deleteStation(String stationId) async {
    try {
      await SupabaseConfig.client
          .from('printer_stations')
          .delete()
          .eq('id', stationId);
      await loadStations();
      return true;
    } catch (e) {
      debugPrint('🖨️ [PRINTER-STATION] Delete error: $e');
      return false;
    }
  }

  // Cek apakah menu item perlu dicetak ke station tertentu
  bool shouldPrintMenuItem(String menuItemName, String stationType) {
    final stns = _stations.where((s) => s.stationType == stationType && s.isActive).toList();
    if (stns.isEmpty) return stationType == 'kasir';
    for (final s in stns) {
      if (s.menuItems.isEmpty) return true;
      if (s.menuItems.any((m) => m.toLowerCase() == menuItemName.toLowerCase())) return true;
    }
    return false;
  }

  // Ambil printer address untuk tipe station tertentu
  String? getPrinterAddress(String stationType) {
    final stns = _stations.where((s) => s.stationType == stationType && s.isActive).toList();
    if (stns.isEmpty) return null;
    return stns.first.printerAddress;
  }

  // Ambil paper width untuk tipe station tertentu
  int getPaperWidth(String stationType) {
    final stns = _stations.where((s) => s.stationType == stationType && s.isActive).toList();
    if (stns.isEmpty) return 58;
    return stns.first.paperWidth;
  }
}