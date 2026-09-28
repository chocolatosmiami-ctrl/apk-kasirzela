import 'package:flutter/material.dart';

class AppTheme {
  // ── CUREVA PALETTE ──────────────────────────────────────────
  // Primary: Teal (signature Cureva)
  static const Color primary        = Color(0xFF00897B); // teal utama
  static const Color primaryLight   = Color(0xFF26A69A); // teal muda
  static const Color primaryDark    = Color(0xFF00695C); // teal gelap
  static const Color primarySurface = Color(0xFFE0F7F4); // teal wash (bg icon, chip)

  // Accent & Status
  static const Color accentMint     = Color(0xFFB2DFDB); // border, frame
  static const Color success        = Color(0xFF26A69A);
  static const Color warning        = Color(0xFFF59E0B);
  static const Color danger         = Color(0xFFEF4444);
  static const Color dangerSurface  = Color(0xFFFCE4EC);

  // Neutrals
  static const Color surfaceLight   = Color(0xFFF5FAFA); // bg halaman
  static const Color cardLight      = Color(0xFFFFFFFF); // bg card
  static const Color borderLight    = Color(0xFFE8F5F3); // border card
  static const Color textPrimary    = Color(0xFF111111);
  static const Color textSecondary  = Color(0xFF6B7280);
  static const Color textMuted      = Color(0xFFBBBBBB);

  // Dark mode
  static const Color surfaceDark    = Color(0xFF0F1A1A);
  static const Color cardDark       = Color(0xFF1A2A2A);
  static const Color borderDark     = Color(0xFF1E3A3A);

  // ── LEGACY ALIASES (supaya semua file lama tidak error) ─────
  // File-file screen masih pakai AppTheme.primaryRed, lightOrange, dll.
  // Alias ini memetakan warna lama → warna Cureva baru.
  static const Color primaryRed     = primary;        // was 0xFFE53935
  static const Color primaryOrange  = primaryLight;   // was 0xFFF57C00
  static const Color accentAmber    = accentMint;     // was 0xFFFFB300
  static const Color darkRed        = primaryDark;    // was 0xFFB71C1C
  static const Color lightOrange    = primarySurface; // was 0xFFFFE0B2

  // ── RADIUS & SPACING ────────────────────────────────────────
  static const double radiusSm  = 8.0;
  static const double radiusMd  = 12.0;
  static const double radiusLg  = 16.0;
  static const double radiusXl  = 20.0;
  static const double radiusPill = 30.0;

  // ── TEXT STYLES ─────────────────────────────────────────────
  static const TextStyle headingLg = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w800,
    color: textPrimary, letterSpacing: -0.5,
  );
  static const TextStyle headingMd = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary,
  );
  static const TextStyle labelSm = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w600, color: textSecondary,
  );
  static const TextStyle priceLg = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary,
  );

  // ── LIGHT THEME ─────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: surfaceLight,

    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primarySurface,
      onPrimaryContainer: primaryDark,
      secondary: primaryLight,
      onSecondary: Colors.white,
      secondaryContainer: primarySurface,
      onSecondaryContainer: primaryDark,
      tertiary: accentMint,
      onTertiary: primaryDark,
      tertiaryContainer: primarySurface,
      onTertiaryContainer: primaryDark,
      error: danger,
      onError: Colors.white,
      errorContainer: dangerSurface,
      onErrorContainer: danger,
      surface: surfaceLight,
      onSurface: textPrimary,
      surfaceContainerHighest: cardLight,
      onSurfaceVariant: textSecondary,
      outline: borderLight,
      outlineVariant: accentMint,
      shadow: Colors.black12,
      inverseSurface: textPrimary,
      onInverseSurface: Colors.white,
      inversePrimary: accentMint,
    ),

    // AppBar — putih bersih seperti Cureva
    appBarTheme: const AppBarTheme(
      backgroundColor: cardLight,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        fontFamily: 'Roboto',
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: primary),
    ),

    // Bottom Navigation — akan di-override di HomeScreen
    // dengan custom pill nav, tapi fallback ini tetap rapi
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: primary,
      unselectedItemColor: textMuted,
      type: BottomNavigationBarType.fixed,
      backgroundColor: cardLight,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 11),
    ),

    // ElevatedButton — teal solid
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'Roboto',
        ),
      ),
    ),

    // OutlinedButton — teal outline
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),

    // TextButton
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
    ),

    // Card — putih, border tipis, radius besar
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: borderLight, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // TextField — bg surfaceLight, focus teal
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: danger),
      ),
      hintStyle: const TextStyle(color: textMuted, fontSize: 13),
      labelStyle: const TextStyle(color: textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),

    // Chip — teal
    chipTheme: ChipThemeData(
      backgroundColor: primarySurface,
      selectedColor: primary,
      labelStyle: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: primaryDark,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusPill),
        side: const BorderSide(color: accentMint),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: cardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXl),
      ),
      titleTextStyle: const TextStyle(
        fontSize: 16, fontWeight: FontWeight.w800,
        color: textPrimary, fontFamily: 'Roboto',
      ),
    ),

    // BottomSheet
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: cardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      elevation: 0,
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: borderLight, thickness: 1, space: 0,
    ),

    // ListTile
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),

    // Switch & Checkbox
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primaryLight : accentMint,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : Colors.transparent,
      ),
      side: const BorderSide(color: borderLight, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),

    // FloatingActionButton
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: CircleBorder(),
    ),

    // ProgressIndicator
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
    ),
  );

  // ── DARK THEME ───────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: surfaceDark,

    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: primaryLight,
      onPrimary: Colors.white,
      primaryContainer: primaryDark,
      onPrimaryContainer: accentMint,
      secondary: accentMint,
      onSecondary: primaryDark,
      secondaryContainer: primaryDark,
      onSecondaryContainer: accentMint,
      tertiary: accentMint,
      onTertiary: primaryDark,
      tertiaryContainer: primaryDark,
      onTertiaryContainer: accentMint,
      error: danger,
      onError: Colors.white,
      errorContainer: Color(0xFF4A1A1A),
      onErrorContainer: danger,
      surface: surfaceDark,
      onSurface: Colors.white,
      surfaceContainerHighest: cardDark,
      onSurfaceVariant: Color(0xFF9CA3AF),
      outline: borderDark,
      outlineVariant: Color(0xFF1E3A3A),
      shadow: Colors.black26,
      inverseSurface: Colors.white,
      onInverseSurface: textPrimary,
      inversePrimary: primaryDark,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: cardDark,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        fontFamily: 'Roboto',
      ),
      iconTheme: IconThemeData(color: primaryLight),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: primaryLight,
      unselectedItemColor: Color(0xFF6B7280),
      type: BottomNavigationBarType.fixed,
      backgroundColor: cardDark,
      elevation: 0,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: borderDark, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: primaryLight, width: 1.5),
      ),
      hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: primaryDark,
      selectedColor: primaryLight,
      labelStyle: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: accentMint,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusPill),
        side: const BorderSide(color: borderDark),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXl),
      ),
      titleTextStyle: const TextStyle(
        fontSize: 16, fontWeight: FontWeight.w800,
        color: Colors.white, fontFamily: 'Roboto',
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      elevation: 0,
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: CircleBorder(),
    ),
  );

  // ── HELPER WIDGETS ──────────────────────────────────────────

  /// Tombol qty bulat gaya Cureva (− / +)
  static Widget qtyButton({
    required IconData icon,
    required VoidCallback onTap,
    bool solid = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: solid ? primary : cardLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: solid ? primary : borderLight,
            width: 1,
          ),
        ),
        child: Icon(
          icon, size: 16,
          color: solid ? Colors.white : primary,
        ),
      ),
    );
  }

  /// Badge stok pojok card menu
  static Widget stockBadge(double stock) {
    final isLow = stock <= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLow ? warning : success,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Sisa ${stock.toInt()}',
        style: const TextStyle(
          color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Chip kategori gaya Cureva
  static Widget categoryChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? primary : cardLight,
          borderRadius: BorderRadius.circular(radiusPill),
          border: Border.all(
            color: selected ? primary : borderLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : textSecondary,
          ),
        ),
      ),
    );
  }

  /// Cart bottom bar — strip hitam dengan info item + tombol bayar
  static Widget cartBar({
    required int itemCount,
    required String previewText,
    required String totalText,
    required VoidCallback onTap,
  }) {
    return Container(
      color: cardLight,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$itemCount item dipilih',
                  style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: textPrimary,
                  ),
                ),
                if (previewText.isNotEmpty)
                  Text(
                    previewText,
                    style: const TextStyle(fontSize: 10, color: textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            totalText,
            style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(radiusMd),
              ),
              child: const Text(
                'Bayar →',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Hero card teal (untuk banner AI Insights di Home)
  static Widget heroBanner({
    required String title,
    required String subtitle,
    required String ctaText,
    required VoidCallback onTap,
    String emoji = '🤖',
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: primary,
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10, top: -10,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(emoji, style: const TextStyle(fontSize: 36)),
                ],
              ),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.18),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(radiusXl),
                    ),
                  ),
                  child: Text(
                    ctaText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}