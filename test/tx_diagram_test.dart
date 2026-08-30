import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/tx_diagram.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';

/// A txid to build outpoints from, so a branch is named the way the
/// chain names it.
const String _prev =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

/// Handle on the layer the diagram paints into, so a test can look at
/// the pixels it produced.
final diagramKey = GlobalKey();

Widget diagramApp({
  required List<TxBranch> inputs,
  required List<TxBranch> outputs,
  int? feeSats,
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final tokens = brightness == Brightness.dark
      ? GerfautTokens.dark
      : GerfautTokens.light;
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(FakeBridge())],
    child: MaterialApp(
      theme: themeFrom(tokens, brightness),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(GerfautSpacing.md),
              child: RepaintBoundary(
                key: diagramKey,
                child: TxDiagram(
                  inputs: inputs,
                  outputs: outputs,
                  feeSats: feeSats,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Every truncated label must be drawn inside the room it was given.
///
/// A label wider than its box is faded by Flutter, and the fade eats
/// the tail — which, for an outpoint, is the `:0` that names the input.
/// Seen on a real phone: the cut was computed from an assumed character
/// width and came out one character too long.
void _labelsFitTheirColumn(WidgetTester tester) {
  var checked = 0;
  for (final element in find.byType(Text).evaluate()) {
    final data = (element.widget as Text).data;
    if (data == null || !data.contains('...')) continue;
    final box = element.renderObject! as RenderBox;
    final room = (box.parent! as RenderBox).size.width;
    expect(
      box.size.width,
      lessThanOrEqualTo(room + 0.5),
      reason: '"$data" is ${box.size.width - room} wider than its column',
    );
    checked++;
  }
  expect(checked, greaterThan(0), reason: 'no truncated label to check');
}

/// The hairline box a node's text sits in.
Finder boxAround(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first;

/// The box a branch of a given role sits in, found by the icon that
/// names that role.
Finder boxOfRole(IconData icon) => find
    .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
    .first;

/// A phone of a given width, the two that matter: the common one and
/// the smallest one still sold.
void useWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The truncated outpoint drawn on the input side, as it reaches the
/// glass. Picked out by the head of the txid it was built from, so an
/// output address cut the same way is never mistaken for it.
String drawnOutpoint(WidgetTester tester) {
  final drawn = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final data = (element.widget as Text).data;
    if (data != null && data.contains('...') && data.startsWith('a1')) {
      drawn.add(data);
    }
  }
  expect(drawn, hasLength(1), reason: 'expected one truncated outpoint');
  return drawn.single;
}

/// A plain payment: one coin of the wallet spent, one payee, one
/// change output back.
List<TxBranch> get _sendInputs => const [
  TxBranch(
    role: TxBranchRole.walletInput,
    label: '$_prev:0',
    sats: 100000,
    mine: true,
  ),
];

List<TxBranch> get _sendOutputs => const [
  TxBranch(
    role: TxBranchRole.externalOutput,
    label: 'bc1qexternalpayeeaddress',
    sats: 90000,
  ),
  TxBranch(
    role: TxBranchRole.change,
    label: 'bc1qchangebackaddress',
    sats: 9000,
    mine: true,
  ),
];

void main() {
  testWidgets('a plain send draws both sides and the fee below', (
    tester,
  ) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(inputs: _sendInputs, outputs: _sendOutputs, feeSats: 1000),
    );
    await tester.pumpAndSettle();

    // The crossroads, then the fee hanging under it.
    expect(find.text('TX'), findsOneWidget);
    expect(find.text('FEE'), findsOneWidget);
    expect(find.text(formatAmount(1000, AmountUnit.btc)), findsOneWidget);
    // A role is an icon, the same one the lists use.
    expect(find.byIcon(LucideIcons.wallet), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowUpRight), findsOneWidget);
    expect(find.byIcon(LucideIcons.undo2), findsOneWidget);
    // Every branch closes on its amount.
    expect(find.text(formatAmount(100000, AmountUnit.btc)), findsOneWidget);
    expect(find.text(formatAmount(90000, AmountUnit.btc)), findsOneWidget);
    expect(find.text(formatAmount(9000, AmountUnit.btc)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one input and one output still converge on the square', (
    tester,
  ) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(
        inputs: _sendInputs,
        outputs: const [
          TxBranch(
            role: TxBranchRole.externalOutput,
            label: 'bc1qexternalpayeeaddress',
            sats: 99000,
          ),
        ],
        feeSats: 1000,
      ),
    );
    await tester.pumpAndSettle();

    // Three columns even with one branch a side: the convergence is
    // the idea, and a stacked variant loses it.
    final square = tester.getRect(boxAround('TX'));
    final input = tester.getRect(boxOfRole(LucideIcons.wallet));
    final output = tester.getRect(boxOfRole(LucideIcons.arrowUpRight));
    expect(input.right, lessThan(square.left));
    expect(output.left, greaterThan(square.right));
    // The junction is a square of the size DESIGN.md fixes, not a card
    // that grows with what it holds.
    expect(square.size, const Size(40, 40));
    // Each side keeps the room its curve needs to turn in.
    expect(square.left - input.right, greaterThanOrEqualTo(40));
    expect(output.left - square.right, greaterThanOrEqualTo(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a receive puts the wallet on the output side', (tester) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(
        inputs: const [
          TxBranch(
            role: TxBranchRole.externalInput,
            label: '$_prev:1',
            sats: 60000,
          ),
        ],
        outputs: const [
          TxBranch(
            role: TxBranchRole.walletOutput,
            label: 'bc1qreceivedhere',
            sats: 50000,
            mine: true,
          ),
        ],
        feeSats: 10000,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.arrowDownLeft), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowUpRight), findsOneWidget);
    expect(find.byIcon(LucideIcons.wallet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a self transfer keeps the wallet on both sides', (tester) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(
        inputs: const [
          TxBranch(
            role: TxBranchRole.walletInput,
            label: '$_prev:0',
            sats: 50000,
            mine: true,
          ),
        ],
        outputs: const [
          TxBranch(
            role: TxBranchRole.walletOutput,
            label: 'bc1qbackwhereitcame',
            sats: 49800,
            mine: true,
          ),
        ],
        feeSats: 200,
      ),
    );
    await tester.pumpAndSettle();

    // Nothing left the wallet: no external role anywhere.
    expect(find.byIcon(LucideIcons.wallet), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowDownLeft), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowUpRight), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a branch of the wallet takes the accent, the rest do not', (
    tester,
  ) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(inputs: _sendInputs, outputs: _sendOutputs, feeSats: 1000),
    );
    await tester.pumpAndSettle();

    BoxDecoration decorationOf(Finder finder) =>
        tester.widget<Container>(finder).decoration! as BoxDecoration;

    // The very wash the input and output lists below the diagram use:
    // a branch is recognized the same way whichever the eye lands on.
    final mine = decorationOf(boxOfRole(LucideIcons.wallet));
    final tokens = GerfautTokens.light;
    expect(mine.color, tokens.primary.withValues(alpha: 0.04));
    expect(
      (mine.border! as Border).top.color,
      tokens.primary.withValues(alpha: 0.4),
    );
    // Anything else is a hairline box on the card surface, the fee
    // node included.
    final other = decorationOf(boxOfRole(LucideIcons.arrowUpRight));
    expect(other.color, tokens.surface);
    expect((other.border! as Border).top.color, tokens.border);
    expect(decorationOf(boxAround('FEE')).color, tokens.surface);
  });

  testWidgets('a coinbase input says the coins are newly minted', (
    tester,
  ) async {
    useWidth(tester, 411);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      diagramApp(
        inputs: const [
          TxBranch(
            role: TxBranchRole.coinbase,
            label: 'Coinbase',
            sats: 312500000,
          ),
        ],
        outputs: const [
          TxBranch(
            role: TxBranchRole.externalOutput,
            label: 'bc1qminerpayout',
            sats: 312500000,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.pickaxe), findsOneWidget);
    // The drawn label is cut to the room the box has; the name a
    // reader is given never is.
    expect(
      find.bySemanticsLabel(
        'Newly minted coins, Coinbase, '
        '${formatAmount(312500000, AmountUnit.btc)}',
      ),
      findsOneWidget,
    );
    // A coinbase pays no fee: no box under the diagram.
    expect(find.text('FEE'), findsNothing);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('a zero fee hangs nothing under the square', (tester) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(inputs: _sendInputs, outputs: _sendOutputs, feeSats: 0),
    );
    await tester.pumpAndSettle();

    // Nothing left the square downward, and nothing says it did.
    expect(find.text('TX'), findsOneWidget);
    expect(find.text('FEE'), findsNothing);
    expect(find.text(formatAmount(0, AmountUnit.btc)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a data output carries the OP_RETURN role', (tester) async {
    useWidth(tester, 411);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      diagramApp(
        inputs: _sendInputs,
        outputs: const [
          TxBranch(
            role: TxBranchRole.externalOutput,
            label: 'bc1qexternalpayeeaddress',
            sats: 98000,
          ),
          TxBranch(role: TxBranchRole.opReturn, label: 'OP_RETURN', sats: 0),
        ],
        feeSats: 2000,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.scrollText), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Data output, OP_RETURN, ${formatAmount(0, AmountUnit.btc)}',
      ),
      findsOneWidget,
    );
    // A payload carries no coins, and the box says so rather than
    // leaving the line blank.
    expect(find.text(formatAmount(0, AmountUnit.btc)), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('both sides fold, and each names the side it stands for', (
    tester,
  ) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(
        inputs: [
          for (var i = 0; i < 12; i++)
            TxBranch(
              role: TxBranchRole.externalInput,
              label: '$_prev:$i',
              sats: 1000,
            ),
        ],
        outputs: [
          for (var i = 0; i < 15; i++)
            TxBranch(
              role: TxBranchRole.externalOutput,
              label: 'bc1qpayee$i',
              sats: 500,
            ),
        ],
        feeSats: 1000,
      ),
    );
    await tester.pumpAndSettle();

    // Five boxes a side, the last of them standing for the rest — and
    // saying which rest, since `+8 more` read halfway down a picture
    // does not say more of what.
    expect(find.text('+8 more inputs'), findsOneWidget);
    expect(find.text('+11 more outputs'), findsOneWidget);
    expect(find.byIcon(LucideIcons.ellipsis), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.arrowUpRight), findsNWidgets(8));
    // Each folded box carries the sum of what it hides.
    expect(find.text(formatAmount(8000, AmountUnit.btc)), findsOneWidget);
    expect(find.text(formatAmount(5500, AmountUnit.btc)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forty inputs fold into one box that carries their sum', (
    tester,
  ) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(
        inputs: [
          for (var i = 0; i < 40; i++)
            TxBranch(
              role: TxBranchRole.externalInput,
              label: '$_prev:$i',
              sats: 1000,
            ),
        ],
        outputs: _sendOutputs,
        feeSats: 1000,
      ),
    );
    await tester.pumpAndSettle();

    // Four branches kept, the other thirty-six behind one box that
    // stands for all of them.
    expect(find.text('+36 more inputs'), findsOneWidget);
    expect(find.byIcon(LucideIcons.ellipsis), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowUpRight), findsNWidgets(5));
    expect(find.text(formatAmount(36000, AmountUnit.btc)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an input nobody can price keeps its box and its outpoint', (
    tester,
  ) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(
        inputs: const [
          TxBranch(
            role: TxBranchRole.externalInput,
            label: '$_prev:0',
            sats: 100000,
          ),
          TxBranch(role: TxBranchRole.externalInput, label: '$_prev:7'),
        ],
        outputs: _sendOutputs,
      ),
    );
    await tester.pumpAndSettle();

    // No value, no invented figure — and no fee node either, since a
    // fee cannot be established without every input.
    expect(find.text('n/a'), findsOneWidget);
    expect(find.text('FEE'), findsNothing);
    expect(find.byIcon(LucideIcons.arrowUpRight), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a folded tail with an unknown value states nothing', (
    tester,
  ) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(
        inputs: [
          for (var i = 0; i < 8; i++)
            TxBranch(
              role: TxBranchRole.externalInput,
              label: '$_prev:$i',
              sats: i == 7 ? null : 1000,
            ),
        ],
        outputs: _sendOutputs,
      ),
    );
    await tester.pumpAndSettle();

    // One unknown among the folded four is enough: their sum would be
    // a guess, so the box says so instead.
    expect(find.text('+4 more inputs'), findsOneWidget);
    expect(find.text('n/a'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 411.0]) {
    testWidgets('a crowded transaction fits a ${width.round()}dp phone', (
      tester,
    ) async {
      useWidth(tester, width);
      await tester.pumpWidget(
        diagramApp(
          inputs: [
            for (var i = 0; i < 40; i++)
              TxBranch(
                role: TxBranchRole.walletInput,
                label: '$_prev:$i',
                sats: 1234567,
                mine: true,
              ),
          ],
          outputs: [
            for (var i = 0; i < 6; i++)
              TxBranch(
                role: TxBranchRole.externalOutput,
                label: 'bc1qaveryverylongbech32addresstopay$i',
                sats: 8123456,
              ),
          ],
          feeSats: 12345,
        ),
      );
      await tester.pumpAndSettle();

      // A diagram that overflows is no longer a diagram.
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TxDiagram)).width,
        lessThanOrEqualTo(width - 2 * GerfautSpacing.md),
      );
      _labelsFitTheirColumn(tester);
    });
  }

  testWidgets('a crowded transaction survives twice the text size', (
    tester,
  ) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(
        inputs: [
          for (var i = 0; i < 12; i++)
            TxBranch(
              role: TxBranchRole.walletInput,
              label: '$_prev:$i',
              sats: 1234567,
              mine: true,
            ),
        ],
        outputs: [
          for (var i = 0; i < 4; i++)
            TxBranch(
              role: TxBranchRole.externalOutput,
              label: 'bc1qaveryverylongbech32addresstopay$i',
              sats: 8123456,
            ),
        ],
        feeSats: 12345,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing overflows: a RenderFlex that spills is reported here as
    // an exception, and a diagram wider than its page would make the
    // whole transaction scroll sideways.
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(TxDiagram)).width,
      lessThanOrEqualTo(411 - 2 * GerfautSpacing.md),
    );
    // The square holds its size, so the two sides keep their room
    // whatever the reader's text setting.
    expect(tester.getSize(boxAround('TX')), const Size(40, 40));
    // The boxes grew instead: two lines of twice the text.
    expect(find.text('+8 more inputs'), findsOneWidget);
    _labelsFitTheirColumn(tester);
  });

  testWidgets('the diagram reads in the dark theme too', (tester) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(
        inputs: _sendInputs,
        outputs: _sendOutputs,
        feeSats: 1000,
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TX'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('TX')).style!.color,
      GerfautTokens.dark.textMuted,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('masking covers every figure of the diagram', (tester) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(inputs: _sendInputs, outputs: _sendOutputs, feeSats: 1000),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TxDiagram)),
      listen: false,
    );
    container.read(maskedProvider.notifier).toggle();
    await tester.pumpAndSettle();

    // Three branches and the fee node.
    expect(find.text(maskedValue), findsNWidgets(4));
    expect(find.text(formatAmount(100000, AmountUnit.btc)), findsNothing);
    // Labels are not a figure: masking hides what a branch carries,
    // never where it went.
    expect(find.byIcon(LucideIcons.wallet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // An outpoint is named by its index, and a fixed tail count kept the
  // `:0` of a first output by luck alone: anything longer was swallowed
  // into the txid's tail, leaving nowhere to see where the index began.
  for (final width in [320.0, 411.0]) {
    for (final vout in [0, 12, 345]) {
      testWidgets('an outpoint keeps vout $vout whole at ${width.round()}dp', (
        tester,
      ) async {
        useWidth(tester, width);
        await tester.pumpWidget(
          diagramApp(
            inputs: [
              TxBranch(
                role: TxBranchRole.walletInput,
                label: '$_prev:$vout',
                sats: 100000,
                mine: true,
              ),
            ],
            outputs: _sendOutputs,
            feeSats: 1000,
          ),
        );
        await tester.pumpAndSettle();

        final drawn = drawnOutpoint(tester);
        expect(
          drawn,
          endsWith(':$vout'),
          reason: '"$drawn" lost the index that names the input',
        );
        // And the head of the txid survived with it: an index alone
        // names nothing either.
        expect(drawn, startsWith('a1'));
        // Whatever came back has to fit, or the fade eats the tail it
        // was cut to protect.
        _labelsFitTheirColumn(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the picture names itself and its two sides', (tester) async {
    useWidth(tester, 411);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      diagramApp(inputs: _sendInputs, outputs: _sendOutputs, feeSats: 1000),
    );
    await tester.pumpAndSettle();

    // Without them a reader walks into a run of outpoints belonging to
    // nothing: which side a box is on is the drawing's doing alone.
    expect(find.bySemanticsLabel('Transaction diagram'), findsOneWidget);
    expect(find.bySemanticsLabel('Inputs'), findsOneWidget);
    expect(find.bySemanticsLabel('Outputs'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the drawing itself is not read out loud', (tester) async {
    useWidth(tester, 411);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      diagramApp(inputs: _sendInputs, outputs: _sendOutputs, feeSats: 1000),
    );
    await tester.pumpAndSettle();

    // Each box says in words what the picture says in shapes.
    expect(
      find.bySemanticsLabel(
        'Spent from this wallet, $_prev:0, '
        '${formatAmount(100000, AmountUnit.btc)}',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Change back to this wallet, bc1qchangebackaddress, '
        '${formatAmount(9000, AmountUnit.btc)}',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the square sits level with the branches it joins', (
    tester,
  ) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(inputs: _sendInputs, outputs: _sendOutputs, feeSats: 1000),
    );
    await tester.pumpAndSettle();

    final diagram = tester.getRect(find.byType(TxDiagram));
    final square = tester.getRect(boxAround('TX'));
    final fee = tester.getRect(boxAround('FEE'));
    final input = tester.getRect(boxOfRole(LucideIcons.wallet));

    // The junction is centred across the width, and the fee node hangs
    // straight under it.
    expect(square.center.dx, closeTo(diagram.center.dx, 1));
    expect(fee.center.dx, closeTo(diagram.center.dx, 1));
    expect(fee.top, greaterThan(square.bottom));
    // A lone input is level with the square its curve reaches.
    expect(input.center.dy, closeTo(square.center.dy, 1));
  });

  testWidgets('the connectors are painted, not merely laid out', (
    tester,
  ) async {
    useWidth(tester, 411);
    await tester.pumpWidget(
      diagramApp(inputs: _sendInputs, outputs: _sendOutputs, feeSats: 1000),
    );
    await tester.pumpAndSettle();

    final diagram = tester.getRect(find.byType(TxDiagram));
    final square = tester.getRect(boxAround('TX'));
    final boundary =
        tester.renderObject(find.byKey(diagramKey)) as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage());
    final pixels = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );

    // A strip of the gutter, clear of both the boxes and the square:
    // the curves are the only thing that can put ink there.
    final x = (square.left - diagram.left - 12).round();
    var inked = 0;
    for (var y = 0; y < diagram.height.round(); y++) {
      final alpha = pixels!.getUint8((y * image!.width + x) * 4 + 3);
      if (alpha > 0) inked += 1;
    }
    expect(inked, greaterThan(0));
  });
}
