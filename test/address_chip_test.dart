import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/address_chip.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The chip in a row of fixed width, the shape that squeezes it.
Widget squeezed(Widget chip, {double width = 200}) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        // Flexible, because a Row hands an inflexible child unbounded
        // width: that is the shape in which the chip is squeezed.
        child: SizedBox(
          width: width,
          child: Row(children: [Flexible(child: chip)]),
        ),
      ),
    ),
  );
}

/// What the chip actually drew.
String drawn(WidgetTester tester) {
  return tester
      .widget<Text>(
        find
            .descendant(
              of: find.byType(AddressChip),
              matching: find.byType(Text),
            )
            .first,
      )
      .data!;
}

/// The chip in the shape that caught the fault: loose constraints, so
/// the chip takes whatever width its content asks for.
Widget host(Widget chip, {TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: Scaffold(
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Align(alignment: Alignment.topLeft, child: chip),
        ),
      ),
    ),
  );
}

void main() {
  const txid =
      'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          return call.method == 'Clipboard.setData' ? null : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('the confirmation does not widen the chip', (tester) async {
    await tester.pumpWidget(
      host(const AddressChip(value: txid, head: 8, tail: 8)),
    );
    final before = tester.getSize(find.byType(AddressChip)).width;

    await tester.tap(find.byType(AddressChip));
    await tester.pump();

    expect(find.text('Copied'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    // The word takes its room from the identifier, which gives it back
    // one whole character at a time: the chip never grows, so nothing
    // beside it in a Wrap is ever pushed to the next line.
    final copiedWidth = tester.getSize(find.byType(AddressChip)).width;
    expect(copiedWidth, lessThanOrEqualTo(before));
    expect(before - copiedWidth, lessThan(20));

    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Copied'), findsNothing);
    expect(tester.getSize(find.byType(AddressChip)).width, closeTo(before, 1));
  });

  testWidgets('it holds its width at a doubled text scale', (tester) async {
    await tester.pumpWidget(
      host(
        const AddressChip(value: txid, head: 8, tail: 8),
        textScaler: const TextScaler.linear(2),
      ),
    );
    final before = tester.getSize(find.byType(AddressChip)).width;

    await tester.tap(find.byType(AddressChip));
    await tester.pump();

    final copiedWidth = tester.getSize(find.byType(AddressChip)).width;
    expect(copiedWidth, lessThanOrEqualTo(before));
    expect(before - copiedWidth, lessThan(40));
    await tester.pump(const Duration(milliseconds: 1600));
  });

  testWidgets('a squeezed chip shortens, it never fades a character', (
    tester,
  ) async {
    await tester.pumpWidget(
      squeezed(const AddressChip(value: txid, head: 12, tail: 10)),
    );

    final shown = drawn(tester);
    final parts = shown.split('...');
    expect(parts, hasLength(2));
    // Both ends are still exactly what is on the chain: a faded tail
    // would have drawn a different identifier.
    expect(txid.startsWith(parts.first), isTrue);
    expect(txid.endsWith(parts.last), isTrue);
    // And it really was shortened to fit the 200px row.
    expect(parts.first.length + parts.last.length, lessThan(22));
    expect(
      tester.getSize(find.byType(AddressChip)).width,
      lessThanOrEqualTo(200),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chip with room keeps the truncation it was asked for', (
    tester,
  ) async {
    await tester.pumpWidget(
      squeezed(const AddressChip(value: txid, head: 12, tail: 10), width: 600),
    );
    expect(drawn(tester), '${txid.substring(0, 12)}...${txid.substring(54)}');
  });

  testWidgets('it copies the whole value, not the truncation', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });

    await tester.pumpWidget(host(const AddressChip(value: txid)));
    await tester.tap(find.byType(AddressChip));
    await tester.pump();

    expect(copied, txid);
    await tester.pump(const Duration(milliseconds: 1600));
  });
}
