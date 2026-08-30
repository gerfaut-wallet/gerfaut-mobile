import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/add_wallet.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/notice.dart';
import 'package:gerfaut/widgets/select_field.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  testWidgets('the continue button scrolls into reach under the keyboard', (
    tester,
  ) async {
    // A 16:9 phone with the keyboard up: the Pixel 2 at 411x731 keeps
    // about 380 logical pixels for the page once the keyboard is open.
    const ratio = 2.625;
    tester.view.physicalSize = const Size(411 * ratio, 731 * ratio);
    tester.view.devicePixelRatio = ratio;
    tester.view.viewInsets = const FakeViewPadding(bottom: 350 * ratio);
    addTearDown(tester.view.reset);

    final bridge = FakeBridge(onParse: (_) => makeParsedInput());
    await tester.pumpWidget(screen(bridge));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wpkh(tpub.../0/*)');
    await tester.pumpAndSettle();

    // Reachable by scrolling, and fully above the keyboard once there.
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Continue')).bottom,
      lessThanOrEqualTo(731 - 350),
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('NAME'), findsOneWidget);
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

  testWidgets('a bare key states its missing script type outside the card', (
    tester,
  ) async {
    final tokens = GerfautTokens.light;
    final bridge = FakeBridge(
      onParseWith: (_, script) => extendedKey(script ?? ScriptKind.segwit),
    );
    await tester.pumpWidget(screen(bridge));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tpubD6NzV...');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // The card says what was recognized; the note is not in it.
    final card = find
        .ancestor(
          of: find.text('First address'),
          matching: find.byType(Container),
        )
        .first;
    expect(
      find.descendant(of: card, matching: find.byType(GerfautNotice)),
      findsNothing,
    );

    // Amber, and reading as a panel rather than as small print.
    final notice = find.byType(GerfautNotice);
    expect(tester.widget<GerfautNotice>(notice).tone, NoticeTone.info);
    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.info)).color,
      tokens.pending,
    );
    expect(
      tester
          .widget<Text>(find.text(InputWarning.assumedSegwit.label))
          .style
          ?.color,
      tokens.pending,
    );

    // Under the card, above the choice it comments on.
    expect(
      tester.getRect(notice).top,
      greaterThanOrEqualTo(tester.getRect(card).bottom),
    );
    expect(
      tester.getRect(find.text('SCRIPT TYPE')).top,
      greaterThanOrEqualTo(tester.getRect(notice).bottom),
    );
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

    // Pick another network first: the re-parse must not reset it. The
    // note pushes the choices past the fold on this small viewport.
    await tester.ensureVisible(find.text('Testnet 4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Testnet 4'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(GerfautSelect<ScriptKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GerfautSelect<ScriptKind>));
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

  testWidgets('a descriptor offers no derivation to change', (tester) async {
    final bridge = FakeBridge(onParse: (_) => makeParsedInput());
    await tester.pumpWidget(screen(bridge));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wpkh(tpub.../0/*)');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Advanced'), findsNothing);
  });

  group('advanced derivation', () {
    ParsedInput loneKey({
      String receive = '0/*',
      String? change = '1/*',
      String? origin,
      String preview = 'tb1q0segwit0preview',
    }) {
      return makeParsedInput(
        kind: RecognizedKind.extendedKey,
        payload: DescriptorsPayload(
          external: 'wpkh(tpub...$receive)#checksum',
          internal: change == null ? null : 'wpkh(tpub...$change)#checksum',
          script: ScriptKind.segwit,
        ),
        scriptOptions: const [ScriptKind.segwit, ScriptKind.taproot],
        previewAddress: preview,
        derivationEditable: true,
        derivation: DerivationChoice(
          receive: receive,
          change: change,
          origin: origin,
        ),
      );
    }

    /// The text a derivation field holds, by its key.
    String pathIn(WidgetTester tester, String field) {
      return tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(Key('derivation.$field')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text;
    }

    Future<void> typePath(
      WidgetTester tester,
      String field,
      String value,
    ) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(Key('derivation.$field')),
          matching: find.byType(TextField),
        ),
        value,
      );
      await tester.pumpAndSettle();
    }

    Future<void> openAdvanced(WidgetTester tester, FakeBridge bridge) async {
      // Tall enough to hold the whole confirm step with the disclosure
      // open: the preview address and any refusal must both be built.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(screen(bridge));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'tpubD6NzV...');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
    }

    testWidgets('the fields start on the paths the core is using', (
      tester,
    ) async {
      final bridge = FakeBridge()
        ..onParseWithOptions = (_, _) =>
            loneKey(origin: "[deadbeef/84'/0'/0']");
      await openAdvanced(tester, bridge);

      expect(pathIn(tester, 'receive'), '0/*');
      expect(pathIn(tester, 'change'), '1/*');
      expect(pathIn(tester, 'origin'), "[deadbeef/84'/0'/0']");
    });

    testWidgets('applying sends the typed paths, an empty change as null', (
      tester,
    ) async {
      final bridge = FakeBridge()
        ..onParseWithOptions = (_, options) => loneKey(
          receive: options.derivation?.receive ?? '0/*',
          change: options.derivation?.change,
          preview: 'tb1q0other0preview',
        );
      await openAdvanced(tester, bridge);

      await typePath(tester, 'receive', '5/*');
      await typePath(tester, 'change', '');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      final applied = bridge.parseOptions.last.derivation!;
      expect(applied.receive, '5/*');
      expect(applied.change, isNull);
      // The card follows the core's answer, never a local guess.
      expect(find.text('tb1q0other0preview'), findsOneWidget);
    });

    testWidgets('a refused path is stated and the card stands', (tester) async {
      var calls = 0;
      final bridge = FakeBridge()
        ..onParseWithOptions = (_, _) {
          calls++;
          if (calls == 1) return loneKey();
          throw const BridgeException(
            'derivation path',
            'invalid derivation path: a hardened step cannot be derived',
          );
        };
      await openAdvanced(tester, bridge);

      await typePath(tester, 'receive', "0'/*");
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('a hardened step cannot be derived'),
        findsOneWidget,
      );
      expect(find.text('tb1q0segwit0preview'), findsOneWidget);
    });

    testWidgets('choosing a script type afterwards keeps the paths', (
      tester,
    ) async {
      final bridge = FakeBridge()
        ..onParseWithOptions = (_, options) =>
            loneKey(receive: options.derivation?.receive ?? '0/*');
      await openAdvanced(tester, bridge);

      await typePath(tester, 'receive', '5/*');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GerfautSelect<ScriptKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ScriptKind.taproot.label).last);
      await tester.pumpAndSettle();

      expect(bridge.parseOptions.last.script, ScriptKind.taproot);
      expect(bridge.parseOptions.last.derivation?.receive, '5/*');
    });
  });
}
