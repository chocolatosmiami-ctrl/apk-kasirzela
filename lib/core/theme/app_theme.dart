import 'package:flutter/material.dart';

// Hallmark v2.0.0: app scope, retained teal brand, Flutter Material controls.
// Critique: persistent navigation labels, readable data, quiet surfaces.
class AppTheme {
  // External platform colors are retained only where the real service is named.
  static const Color deliveryGojek = Color(0xFF00AA13);
  static const Color deliveryGrab = Color(0xFF00B14F);
  static const Color deliveryShopee = Color(0xFFEE4D2D);
  static const Color whatsApp = Color(0xFF25D366);
  static const Color information = Color(0xFF1565C0);
  static const Color informationSurface = Color(0xFFEEF2FF);
  static const Color reservedInk = Color(0xFF6A1B9A);
  static const Color onActionMuted = Color(0xCCFFFFFF);
  static const String fontBody = 'Roboto';
  static const Color onAction = Color(0xFFFFFFFF);
  static const Color transparent = Color(0x00000000);
  static const Color fieldBorder = Color(0xFF7B8D87);
  static const Color warningInk = Color(0xFF845500);
  static const Color warningSurface = Color(0xFFFFF3D6);
  static const double touchTarget = 48;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  // ── ZELA PALETTE ──────────────────────────────────────────
  // Primary: Teal (signature Zela)
  static const Color primary = Color(0xFF00796B); // teal utama
  static const Color primaryLight = Color(0xFF00796B); // teal muda
  static const Color primaryDark = Color(0xFF00695C); // teal gelap
  static const Color primarySurface = Color(
    0xFFEAF5F1,
  ); // teal wash (bg icon, chip)

  // Accent & Status
  static const Color accentMint = Color(0xFFB2DFDB); // border, frame
  static const Color success = Color(0xFF00796B);
  static const Color warning = Color(0xFF845500);
  static const Color danger = Color(0xFFBA3A3A);
  static const Color dangerSurface = Color(0xFFFBEDEC);

  // Neutrals
  static const Color surfaceLight = Color(0xFFF7F9F8); // bg halaman
  static const Color cardLight = Color(0xFFFFFFFF); // bg card
  static const Color borderLight = Color(0xFFDEE7E3); // border card
  static const Color textPrimary = Color(0xFF172B2A);
  static const Color textSecondary = Color(0xFF62736F);
  static const Color textMuted = Color(0xFF62736F);

  // Dark mode
  static const Color surfaceDark = Color(0xFF0F1A1A);
  static const Color cardDark = Color(0xFF1A2A2A);
  static const Color borderDark = Color(0xFF1E3A3A);

  // ── LEGACY ALIASES (supaya semua file lama tidak error) ─────
  // File-file screen masih pakai AppTheme.primaryRed, lightOrange, dll.
  // Alias ini memetakan warna lama → warna Zela baru.
  static const Color primaryRed = primary; // was 0xFFE53935
  static const Color primaryOrange = primaryLight; // was 0xFFF57C00
  static const Color accentAmber = accentMint; // was 0xFFFFB300
  static const Color darkRed = primaryDark; // was 0xFFB71C1C
  static const Color lightOrange = primarySurface; // was 0xFFFFE0B2

  // ── RADIUS & SPACING ────────────────────────────────────────
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;
  static const double radiusPill = 30.0;

  // ── TEXT STYLES ─────────────────────────────────────────────
  static const TextStyle headingLg = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
  );
  static const TextStyle headingMd = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );
  static const TextStyle labelSm = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textSecondary,
  );
  static const TextStyle priceLg = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: textPrimary,
  );

  // ── LIGHT THEME ─────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        splashFactory: InkRipple.splashFactory,
        fontFamily: fontBody,
        scaffoldBackgroundColor: surfaceLight,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16, height: 1.4, color: textPrimary),
          bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: textPrimary),
          bodySmall: TextStyle(fontSize: 12, height: 1.4, color: textSecondary),
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          labelLarge: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: borderLight,
            disabledForegroundColor: textSecondary,
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: primary,
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: cardLight,
          surfaceTintColor: transparent,
          indicatorColor: primarySurface,
          elevation: 0,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: textPrimary,
          contentTextStyle: TextStyle(fontSize: 14, color: onAction),
          actionTextColor: accentMint,
          behavior: SnackBarBehavior.floating,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: primaryDark,
          unselectedLabelColor: textSecondary,
          indicatorColor: primary,
          dividerColor: borderLight,
          labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 14),
        ),

        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        focusColor: accentMint,
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

        // AppBar — putih bersih seperti Zela
        appBarTheme: const AppBarTheme(
          backgroundColor: cardLight,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: fontBody,
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
          selectedLabelStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle: TextStyle(fontSize: 12),
        ),

        // ElevatedButton — teal solid
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusLg),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: fontBody,
            ),
          ),
        ),

        // OutlinedButton — teal outline
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            minimumSize: const Size(48, 48),
            side: const BorderSide(color: primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusLg),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),

        // TextButton
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            minimumSize: const Size(48, 48),
          ),
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
          constraints: const BoxConstraints(minHeight: touchTarget),
          filled: true,
          fillColor: cardLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: fieldBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: fieldBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: danger),
          ),
          hintStyle: const TextStyle(color: textMuted, fontSize: 14),
          labelStyle: const TextStyle(color: textSecondary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),

        // Chip — teal
        chipTheme: ChipThemeData(
          backgroundColor: primarySurface,
          selectedColor: primary,
          checkmarkColor: onAction,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: primaryDark,
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
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: textPrimary,
            fontFamily: fontBody,
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
          color: borderLight,
          thickness: 1,
          space: 0,
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
            (s) =>
                s.contains(WidgetState.selected) ? primary : Colors.transparent,
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
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: primary),
      );

  // ── DARK THEME ───────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        splashFactory: InkRipple.splashFactory,
        fontFamily: fontBody,
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
          onSurfaceVariant: Color(0xFF62736F),
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
            fontFamily: fontBody,
          ),
          iconTheme: IconThemeData(color: primaryLight),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: primaryLight,
          unselectedItemColor: Color(0xFF62736F),
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
          hintStyle: const TextStyle(color: Color(0xFF62736F), fontSize: 13),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: primaryDark,
          selectedColor: primaryLight,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: accentMint,
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
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontFamily: fontBody,
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

  /// Tombol qty bulat gaya Zela (− / +)
  static Widget qtyButton({
    required IconData icon,
    required VoidCallback onTap,
    bool solid = false,
  }) {
    return IconButton.filledTonal(
      tooltip: icon == Icons.remove ? 'Kurangi jumlah' : 'Tambah jumlah',
      onPressed: onTap,
      style: IconButton.styleFrom(
        minimumSize: const Size(touchTarget, touchTarget),
        backgroundColor: solid ? primary : primarySurface,
        foregroundColor: solid ? onAction : primaryDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      icon: Icon(icon, size: 22),
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
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Chip kategori gaya Zela
  static Widget categoryChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: true,
      labelStyle: TextStyle(
        color: selected ? onAction : textPrimary,
        fontSize: 14,
      ),
      selectedColor: primary,
      backgroundColor: cardLight,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  /// Cart bottom bar — strip hitam dengan info item + tombol bayar
  static Widget cartBar({
    required int itemCount,
    required String previewText,
    required String totalText,
    required VoidCallback onTap,
    String actionLabel = 'Bayar',
    VoidCallback? onViewCart,
  }) {
    return ColoredBox(
        color: cardLight,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(spaceMd),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('$itemCount item dipilih', style: labelSm),
                    ),
                    const SizedBox(width: spaceSm),
                    Flexible(
                      child: Text(
                        totalText,
                        style: priceLg,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
                if (previewText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        previewText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelSm,
                      ),
                    ),
                  ),
                const SizedBox(height: spaceSm),
                Row(children: [
                  if (onViewCart != null) ...[
                    TextButton(
                        onPressed: onViewCart, child: const Text('Keranjang')),
                    const SizedBox(width: spaceSm),
                  ],
                  Expanded(
                      child: FilledButton(
                          onPressed: onTap, child: Text(actionLabel))),
                ]),
              ],
            ),
          ),
        ));
  }

  /// Hero card teal (untuk banner AI Insights di Home)
  static Widget heroBanner({
    required String title,
    required String subtitle,
    required String ctaText,
    required VoidCallback onTap,
    String emoji = '🤖',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: spaceMd),
      child: ListTile(
        contentPadding: const EdgeInsets.all(spaceMd),
        leading: const Icon(Icons.insights_outlined, color: primary),
        title: Text(title, style: headingMd),
        subtitle: Text('$subtitle\n$ctaText', style: labelSm),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        tileColor: primarySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
    );
  }
}
