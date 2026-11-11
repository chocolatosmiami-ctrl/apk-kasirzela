import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/theme/app_theme.dart';
import '../lib/core/theme/zela_navigation.dart';
import '../lib/core/theme/zela_product_grid.dart';

void main() {
  testWidgets(
      'product grid keeps readable tiles in a narrow pane and with large text',
      (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final minWidth in [160.0, 216.0]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: 296,
                      child: GridView.builder(
                          gridDelegate: ZelaProductGridDelegate(
                              minItemWidth: minWidth, mainAxisExtent: 300),
                          itemCount: 2,
                          itemBuilder: (_, i) =>
                              SizedBox(key: ValueKey('tile-$i'))))))));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('tile-0'))).width, 296);
      expect(
          tester.getTopLeft(find.byKey(const ValueKey('tile-1'))).dy,
          greaterThan(
              tester.getTopLeft(find.byKey(const ValueKey('tile-0'))).dy));
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'small phone keeps labels and forwards normal and overflow actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = -1;
      var overflow = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 480),
              textScaler: TextScaler.linear(1.8),
              disableAnimations: true,
            ),
            child: Scaffold(
              bottomNavigationBar: ZelaNavigation(
                destinations: [
                  for (final label in [
                    'Home',
                    'Kasir',
                    'Shift',
                    'Riwayat',
                    'Stok',
                    'Pengaturan',
                  ])
                    NavigationDestination(
                      icon: const Icon(Icons.storefront),
                      label: label,
                    ),
                ],
                selectedIndex: 5,
                onSelected: (value) => selected = value,
                onOverflow: () => overflow++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Home', 'Kasir', 'Shift', 'Riwayat', 'Lainnya']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Kasir'));
      expect(selected, 1);
      await tester.tap(find.text('Lainnya'));
      expect(overflow, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('payment summary fits long totals and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var payments = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            bottomNavigationBar: AppTheme.cartBar(
              itemCount: 12,
              previewText: 'Ringkasan pesanan',
              totalText: 'Rp 12.345.678',
              onTap: () => payments++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar'));
    expect(payments, 1);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });
}
