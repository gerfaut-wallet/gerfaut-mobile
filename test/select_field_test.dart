import 'package:flutter/material.dart';

import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/select_field.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A field with two groups, one option out of reach, driven by a
/// stateful host so the value follows the pick.
class _Host extends StatefulWidget {
  const _Host({required this.picked, this.grouped = true});

  final List<String> picked;
  final bool grouped;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String _value = 'eur';

  @override
  Widget build(BuildContext context) {
    const first = [
      GerfautSelectItem(value: 'eur', title: 'EUR', subtitle: 'Euro'),
      GerfautSelectItem(value: 'usd', title: 'USD', subtitle: 'US dollar'),
    ];
    const second = [
      GerfautSelectItem(
        value: 'ngn',
        title: 'NGN',
        subtitle: 'Nigerian naira',
        icon: LucideIcons.gem,
      ),
      GerfautSelectItem(
        value: 'xxx',
        title: 'XXX',
        subtitle: 'Nobody quotes it',
        enabled: false,
      ),
    ];
    void onChanged(String value) {
      widget.picked.add(value);
      setState(() => _value = value);
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Above'),
            widget.grouped
                ? GerfautSelect<String>(
                    label: 'Display currency',
                    value: _value,
                    groups: const [
                      GerfautSelectGroup(label: 'Every source', items: first),
                      GerfautSelectGroup(
                        label: 'CoinGecko only',
                        items: second,
                      ),
                    ],
                    onChanged: onChanged,
                  )
                : GerfautSelect<String>.items(
                    label: 'Display currency',
                    value: _value,
                    items: const [...first, ...second],
                    onChanged: onChanged,
                  ),
          ],
        ),
      ),
    );
  }
}

Widget host(List<String> picked, {bool grouped = true}) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: _Host(picked: picked, grouped: grouped),
  );
}

/// A phone: the options rise as a sheet.
void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The row container carrying the option titled [title]. The current
/// title also sits in the field, so the menu's copy is the last one.
Container rowOf(WidgetTester tester, String title) {
  return tester.widget<Container>(
    find
        .ancestor(of: find.text(title).last, matching: find.byType(Container))
        .first,
  );
}

void main() {
  testWidgets('the field reads as an input and names its value', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host([]));

    expect(tester.getSize(find.byType(GerfautSelect<String>)).height, 44);
    expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    expect(find.text('EUR'), findsOneWidget);
    expect(find.text('Euro'), findsOneWidget);

    final semantics = tester.getSemantics(find.byType(GerfautSelect<String>));
    expect(semantics.label, 'Display currency');
    expect(semantics.value, 'EUR, Euro');
    expect(semantics.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('a wide screen opens an anchored menu and picks', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(host(picked));

    await tester.tap(find.byType(GerfautSelect<String>));
    await tester.pumpAndSettle();

    // A floating card, not a sheet: the page stays in view.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Above'), findsOneWidget);
    expect(find.text('EVERY SOURCE'), findsOneWidget);
    expect(find.text('COINGECKO ONLY'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('US dollar'), findsOneWidget);

    // The current option is the one checked, on a sunken row.
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    final selectedRow = rowOf(tester, 'EUR');
    expect(
      (selectedRow.decoration! as BoxDecoration).color,
      GerfautTokens.light.surfaceSunken,
    );
    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.check)).color,
      GerfautTokens.light.primary,
    );
    expect((rowOf(tester, 'USD').decoration! as BoxDecoration).color, isNull);

    // The menu sits under the field.
    final fieldBottom = tester
        .getBottomLeft(find.byType(GerfautSelect<String>))
        .dy;
    final menuTop = tester.getTopLeft(find.text('EVERY SOURCE')).dy;
    expect(menuTop, greaterThan(fieldBottom));

    await tester.tap(find.text('USD'));
    await tester.pumpAndSettle();

    expect(picked, ['usd']);
    expect(find.text('EVERY SOURCE'), findsNothing);
    expect(find.text('USD'), findsOneWidget);
    expect(find.text('US dollar'), findsOneWidget);
  });

  testWidgets('a disabled option is muted and takes no tap', (tester) async {
    final handle = tester.ensureSemantics();
    final picked = <String>[];
    await tester.pumpWidget(host(picked));

    await tester.tap(find.byType(GerfautSelect<String>));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('XXX')).style!.color,
      GerfautTokens.light.textMuted,
    );
    expect(
      tester.widget<Text>(find.text('NGN')).style!.color,
      GerfautTokens.light.text,
    );
    // The leading icon rides along.
    expect(find.byIcon(LucideIcons.gem), findsOneWidget);
    final row = tester.getSemantics(find.text('XXX'));
    expect(row.flagsCollection.isEnabled, Tristate.isFalse);
    expect(row.label, 'XXX, Nobody quotes it');
    final current = tester.getSemantics(find.text('EUR').last);
    expect(current.flagsCollection.isSelected, Tristate.isTrue);

    await tester.tap(find.text('XXX'));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    // Still open: nothing was picked.
    expect(find.text('EVERY SOURCE'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('EVERY SOURCE'), findsNothing);
    expect(picked, isEmpty);
    handle.dispose();
  });

  testWidgets('a phone opens a bottom sheet with a handle', (tester) async {
    usePhone(tester);
    final picked = <String>[];
    await tester.pumpWidget(host(picked));

    await tester.tap(find.byType(GerfautSelect<String>));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(
      (sheet.shape! as RoundedRectangleBorder).borderRadius,
      const BorderRadius.vertical(top: Radius.circular(16)),
    );
    // The field's label heads the sheet.
    expect(find.text('DISPLAY CURRENCY'), findsOneWidget);
    expect(find.text('EVERY SOURCE'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);

    await tester.tap(find.text('NGN'));
    await tester.pumpAndSettle();

    expect(picked, ['ngn']);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byIcon(LucideIcons.gem), findsOneWidget);
  });

  testWidgets('a lone group shows no header and no divider', (tester) async {
    await tester.pumpWidget(host([], grouped: false));

    await tester.tap(find.byType(GerfautSelect<String>));
    await tester.pumpAndSettle();

    expect(find.text('EVERY SOURCE'), findsNothing);
    expect(find.byType(Divider), findsNothing);
    expect(find.text('USD'), findsOneWidget);
    expect(find.text('NGN'), findsOneWidget);
  });
}
