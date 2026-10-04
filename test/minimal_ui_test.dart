import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/theme/app_theme.dart';
import '../lib/core/theme/minimal_ui.dart';

void main() {
  testWidgets('PIN panel scrolls on a small phone with large text and keyboard', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final digits = <String>[];
    var submits = 0;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
      home: MediaQuery(data: const MediaQueryData(size: Size(320, 480),
        textScaler: TextScaler.linear(1.8), viewInsets: EdgeInsets.only(bottom: 160)),
        child: Scaffold(body: ZelaPinPanel(title: 'Verifikasi PIN', name: 'Amelia',
          subtitle: 'Masukkan PIN Anda untuk melanjutkan.', pin: '1234',
          onDigit: digits.add, onErase: () {}, onSubmit: () => submits++)))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('1'));
    await tester.tap(find.text('1'));
    expect(digits, ['1']);
    await tester.ensureVisible(find.text('Lanjutkan'));
    await tester.tap(find.text('Lanjutkan'));
    expect(submits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIN entry and submit cannot fire while validation is busy', (tester) async {
    var actions = 0;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
      home: Scaffold(body: ZelaPinPanel(title: 'Verifikasi PIN', name: 'Kasir',
        subtitle: 'Memeriksa PIN', pin: '1234', busy: true,
        onDigit: (_) => actions++, onErase: () => actions++, onSubmit: () => actions++))));
    await tester.pump();
    await tester.tap(find.text('1'));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(actions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIN values are masked in semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
      home: Scaffold(body: ZelaPinPanel(title: 'Verifikasi PIN', name: 'Kasir',
        subtitle: 'Masukkan PIN', pin: '987654', onDigit: (_) {},
        onErase: () {}, onSubmit: () {}))));
    expect(find.text('987654'), findsNothing);
    expect(find.bySemanticsLabel('6 digit PIN terisi'), findsOneWidget);
  });

  testWidgets('Tablet frame bounds content without changing scroll behavior', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const bodyKey = ValueKey('body');
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
      home: Scaffold(body: ZelaPage(child: ListView(key: bodyKey,
        children: List.generate(30, (i) => ListTile(title: Text('Baris $i'))))))));
    expect(tester.getSize(find.byKey(bodyKey)).width, 1100);
    await tester.scrollUntilVisible(find.text('Baris 29'), 400);
    expect(find.text('Baris 29'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
