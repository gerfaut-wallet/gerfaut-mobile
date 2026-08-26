import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/add_wallet.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';

import 'fakes.dart';

Widget screen(FakeBridge bridge) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const AddWalletScreen(),
    ),
  );
}

void main() {
  testWidgets('pasting material reaches the confirmation step', (tester) async {
    final bridge = FakeBridge(onParse: (_) => makeParsedInput());
    await tester.pumpWidget(screen(bridge));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'wpkh([9a6a2580/84h/1h/0h]tpub.../0/*)',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Confirmation step: recognized card, name field, network candidates.
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('NETWORK'), findsOneWidget);
    expect(find.text('Signet'), findsOneWidget);
    expect(find.text('Testnet 4'), findsOneWidget);
    expect(find.text('Add wallet'), findsOneWidget);
    // A descriptor fixes its script type: no choice is offered.
    expect(find.text('SCRIPT TYPE'), findsNothing);
  });

  ParsedInput extendedKey(ScriptKind script) {
    return makeParsedInput(
      kind: RecognizedKind.extendedKey,
      payload: DescriptorsPayload(
        external: '${script.id}(tpub.../0/*)#checksum',
        internal: '${script.id}(tpub.../1/*)#checksum',
        script: script,
      ),
      warnings: script == ScriptKind.segwit
          ? const [InputWarning.assumedSegwit]
          : const [],
      scriptOptions: const [
        ScriptKind.legacy,
        ScriptKind.nestedSegwit,
        ScriptKind.segwit,
        ScriptKind.taproot,
      ],
      previewAddress: script == ScriptKind.taproot
          ? 'tb1p0taproot0preview'
          : 'tb1q0segwit0preview',
    );
  }

  testWidgets('a lone extended key offers the script type choice', (
    tester,
  ) async {
    final bridge = FakeBridge(
      onParseWith: (_, script) => extendedKey(script ?? ScriptKind.segwit),
    );
    await tester.pumpWidget(screen(bridge));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tpubD6NzV...');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('First address'), findsOneWidget);
    expect(find.text('tb1q0segwit0preview'), findsOneWidget);
    expect(
      find.text(
        'This key carries no script type: check the one selected below.',
      ),
      findsOneWidget,
    );
    expect(find.text('SCRIPT TYPE'), findsOneWidget);
    expect(find.text('Native SegWit (P2WPKH)'), findsWidgets);
    expect(
      find.text('Compare the first address above with your wallet.'),
      findsOneWidget,
    );
    expect(bridge.parseScripts, [null]);
  });

  testWidgets('choosing a script type re-parses through the core', (
    tester,
  ) async {
    final bridge = FakeBridge(
      onParseWith: (_, script) => extendedKey(script ?? ScriptKind.segwit),
    );
    await tester.pumpWidget(screen(bridge));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tpubD6NzV...');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Pick another network first: the re-parse must not reset it.
    await tester.tap(find.text('Testnet 4'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<ScriptKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taproot (P2TR)').last);
    await tester.pumpAndSettle();

    expect(bridge.parseScripts, [null, ScriptKind.taproot]);
    // The core answered with new descriptors and a new first address.
    expect(find.text('tb1p0taproot0preview'), findsOneWidget);
    expect(find.text('tb1q0segwit0preview'), findsNothing);
    expect(find.textContaining('Taproot (P2TR)'), findsWidgets);
    expect(
      find.text(
        'This key carries no script type: check the one selected below.',
      ),
      findsNothing,
    );

    // Adding uses the re-parsed material on the network kept.
    await tester.enterText(find.byType(TextField), 'Hot');
    await tester.pumpAndSettle();
    // The selectable preview address scrolls on its own: drag the
    // step's list rather than any scrollable.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add wallet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add wallet'));
    await tester.pumpAndSettle();
    expect(bridge.addWalletCalls, 1);
    expect(bridge.wallets.single.network, Network.testnet4);
  });

  testWidgets('private material rejection shows the core message', (
    tester,
  ) async {
    const message = 'input contains private key material and was rejected';
    final bridge = FakeBridge(
      onParse: (_) => throw const BridgeException('private_material', message),
    );
    await tester.pumpWidget(screen(bridge));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'xprv9s21ZrQH...');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    // Still on the input step.
    expect(find.text('NAME'), findsNothing);
  });
}
