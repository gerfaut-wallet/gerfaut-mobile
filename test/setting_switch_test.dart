import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/setting_switch.dart';

Widget host(Widget child) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('a settings switch is read with its name and its line', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final flips = <bool>[];
    await tester.pumpWidget(
      host(
        Column(
          children: [
            SettingSwitch(
              title: 'App lock',
              hint: 'Asked when Gerfaut opens.',
              value: false,
              onChanged: flips.add,
            ),
            SettingSwitch(
              title: 'Disguise the app',
              value: true,
              onChanged: flips.add,
            ),
          ],
        ),
      ),
    );

    // One node per setting: the switch carries the words beside it, so
    // two switches in a card are never two anonymous "off, switch".
    final lock = tester.getSemantics(find.byType(Switch).first);
    expect(lock.label, 'App lock\nAsked when Gerfaut opens.');
    expect(lock.flagsCollection.isToggled, Tristate.isFalse);
    final disguise = tester.getSemantics(find.byType(Switch).last);
    expect(disguise.label, 'Disguise the app');
    expect(disguise.flagsCollection.isToggled, Tristate.isTrue);

    await tester.tap(find.byType(Switch).first);
    expect(flips, [true]);
    handle.dispose();
  });

  testWidgets('a switch that cannot move is greyed and says nothing new', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        const SettingSwitch(
          title: 'New transactions',
          hint: 'Off while the app is disguised.',
          value: true,
          onChanged: null,
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(Switch));
    expect(node.label, 'New transactions\nOff while the app is disguised.');
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    handle.dispose();
  });
}
