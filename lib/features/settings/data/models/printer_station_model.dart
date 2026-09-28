class PrinterStationModel {
  final String? id;
  final String branchId;
  final String ownerId;
  final String name;
  final String stationType; // 'kasir', 'dapur', 'checker'
  final String? printerName;
  final String? printerAddress;
  final int paperWidth;
  final bool isActive;
  final bool autoPrint;
  final List<String> menuItems;

  PrinterStationModel({
    this.id,
    required this.branchId,
    required this.ownerId,
    required this.name,
    required this.stationType,
    this.printerName,
    this.printerAddress,
    this.paperWidth = 58,
    this.isActive = true,
    this.autoPrint = true,
    this.menuItems = const [],
  });

  factory PrinterStationModel.fromMap(Map<String, dynamic> map) {
    return PrinterStationModel(
      id:             map['id']?.toString(),
      branchId:       map['branch_id']?.toString() ?? '',
      ownerId:        map['owner_id']?.toString() ?? '',
      name:           map['name']?.toString() ?? '',
      stationType:    map['station_type']?.toString() ?? 'kasir',
      printerName:    map['printer_name']?.toString(),
      printerAddress: map['printer_address']?.toString(),
      paperWidth:     (map['paper_width'] as num? ?? 58).toInt(),
      isActive:       map['is_active'] as bool? ?? true,
      autoPrint:      map['auto_print'] as bool? ?? true,
      menuItems:      (map['menu_items'] as List<dynamic>? ?? [])
                        .map((e) => e.toString())
                        .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'branch_id':       branchId,
    'owner_id':        ownerId,
    'name':            name,
    'station_type':    stationType,
    'printer_name':    printerName,
    'printer_address': printerAddress,
    'paper_width':     paperWidth,
    'is_active':       isActive,
    'auto_print':      autoPrint,
  };

  String get stationIcon {
    switch (stationType) {
      case 'dapur':   return '👨‍🍳';
      case 'checker': return '✅';
      default:        return '🧾';
    }
  }

  String get stationLabel {
    switch (stationType) {
      case 'dapur':   return 'Dapur';
      case 'checker': return 'Checker';
      default:        return 'Kasir';
    }
  }

  PrinterStationModel copyWith({
    String? id, String? branchId, String? ownerId, String? name,
    String? stationType, String? printerName, String? printerAddress,
    int? paperWidth, bool? isActive, bool? autoPrint, List<String>? menuItems,
  }) => PrinterStationModel(
    id:             id ?? this.id,
    branchId:       branchId ?? this.branchId,
    ownerId:        ownerId ?? this.ownerId,
    name:           name ?? this.name,
    stationType:    stationType ?? this.stationType,
    printerName:    printerName ?? this.printerName,
    printerAddress: printerAddress ?? this.printerAddress,
    paperWidth:     paperWidth ?? this.paperWidth,
    isActive:       isActive ?? this.isActive,
    autoPrint:      autoPrint ?? this.autoPrint,
    menuItems:      menuItems ?? this.menuItems,
  );
}