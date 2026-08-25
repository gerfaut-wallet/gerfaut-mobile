import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/export.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/share.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';

import 'fakes.dart';

/// Records share calls instead of touching the platform plugins.
class FakeCsvSharer implements CsvSharer {
  final List<({String csv, String filename})> shared = [];

  @override
  Future<void> shareCsv({required String csv, required String filename}) async {
    shared.add((csv: csv, filename: filename));
  }
}

TxSummary tx(String txid, int netSats, {int? timestamp}) {
  return TxSummary(
    txid: txid,
    netSats: netSats,
    feeSats: null,
    status: timestamp == null
        ? const TxStatus.pending()
        : TxStatus.confirmed(height: 100, timestamp: timestamp),
    confirmations: timestamp == null ? 0 : 3,
  );
}

Widget exportApp(FakeBridge bridge, FakeCsvSharer sharer) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      csvSharerProvider.overrideWithValue(sharer),
    ],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const ExportScreen(walletId: 'w1'),
    ),
  );
}

FakeBridge makeBridge({bool truncated = false}) {
  final meta = makeMeta();
  return FakeBridge(
    wallets: [meta],
    snapshots: {
      'w1': makeSnapshot(
        meta: meta,
        txs: [
          tx('a' * 64, 5000, timestamp: 1755000000),
          tx('b' * 64, -3000, timestamp: 1755100000),
          tx('c' * 64, 700),
        ],
        truncated: truncated,
      ),
    },
  );
}

void main() {
  testWidgets('the counter mirrors the direction and pending filters', (
    tester,
  ) async {
    final sharer = FakeCsvSharer();
    await tester.pumpWidget(exportApp(makeBridge(), sharer));
    await tester.pumpAndSettle();

    expect(find.text('3 of 3 transactions selected'), findsOneWidget);

    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 transactions selected'), findsOneWidget);

    await tester.tap(find.text('Received'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 transactions selected'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 transactions selected'), findsOneWidget);

    // Dropping pending keeps only the confirmed rows.
    final pendingSwitch = find.byType(Switch).first;
    await tester.tap(pendingSwitch);
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 transactions selected'), findsOneWidget);
  });

  testWidgets('a date bound excludes pending and disables an empty export', (
    tester,
  ) async {
    final sharer = FakeCsvSharer();
    await tester.pumpWidget(exportApp(makeBridge(), sharer));
    await tester.pumpAndSettle();

    // Picking today as the lower bound leaves the 2025 transactions and
    // the undated pending row out: nothing passes.
    await tester.tap(find.text('From'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('0 of 3 transactions selected'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Export CSV'),
    );
    expect(button.onPressed, isNull);

    // Clearing the bound restores the full selection.
    await tester.tap(find.bySemanticsLabel('Clear From date'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 transactions selected'), findsOneWidget);
  });

  testWidgets('the premium teaser is present, sober and disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sharer = FakeCsvSharer();
    await tester.pumpWidget(exportApp(makeBridge(), sharer));
    await tester.pumpAndSettle();

    expect(find.text('Fiat value at transaction time'), findsOneWidget);
    expect(find.text('PREMIUM'), findsOneWidget);
    expect(
      find.textContaining('Coming with the Gerfaut server.'),
      findsOneWidget,
    );

    // The premium switch is off and inert; the pending one still works.
    final switches = tester
        .widgetList<Switch>(find.byType(Switch))
        .toList();
    expect(switches, hasLength(2));
    expect(switches.last.onChanged, isNull);
    expect(switches.last.value, isFalse);
    expect(switches.first.onChanged, isNotNull);
  });

  testWidgets('exporting shares the file and states the row count', (
    tester,
  ) async {
    final sharer = FakeCsvSharer();
    final bridge = makeBridge();
    await tester.pumpWidget(exportApp(bridge, sharer));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();

    expect(bridge.exportCalls, hasLength(1));
    expect(sharer.shared, hasLength(1));
    expect(sharer.shared.single.filename, 'cold-storage-transactions.csv');
    expect(sharer.shared.single.csv, contains('txid,date_utc'));
    expect(find.text('3 transactions exported'), findsOneWidget);

    // Flush the snackbar timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a partial history warns before exporting', (tester) async {
    final sharer = FakeCsvSharer();
    await tester.pumpWidget(exportApp(makeBridge(truncated: true), sharer));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Only the loaded transactions export. Load older rounds first '
        'for a complete file.',
      ),
      findsOneWidget,
    );
  });
}
