import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/screens/settings/notifications_section.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/live.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/notifications.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/select_field.dart';

import 'fakes.dart';

/// Records what would have been posted, and answers the permission the
/// way a test asks it to.
class FakeNotifications implements NotificationService {
  FakeNotifications({this.granted = true});

  bool granted;
  int inits = 0;
  int permissionAsks = 0;
  final List<({int id, String title, String body})> posted = [];

  @override
  Future<void> init() async => inits++;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return granted;
  }

  @override
  Future<void> show(int id, String title, String body) async {
    posted.add((id: id, title: title, body: body));
  }

  @override
  Future<void> cancelAll() async => posted.clear();
}

NewTx tx(int sats, {String txid = 'a', bool confirmed = true}) =>
    NewTx(txid: txid, netSats: sats, confirmed: confirmed);

/// What the core hands out for the new transactions of these reports,
/// with nothing announced before.
List<LiveTx> claimed(List<SyncReport> reports) => [
  for (final report in reports)
    for (final tx in report.newTxs)
      LiveTx(
        walletId: report.walletId,
        txid: tx.txid,
        netSats: tx.netSats,
        stage: tx.confirmed ? TxStage.confirmed : TxStage.mempool,
      ),
];

SyncReport report(List<NewTx> txs, {String id = 'w1'}) => SyncReport(
  walletId: id,
  newTxCount: txs.length,
  newTxs: txs,
  balance: makeBalance(0),
  tipHeight: 100,
  tookMs: 1,
  backend: 'mempool.space',
);

List<String> bodies(
  List<SyncReport> reports, {
  AmountUnit unit = AmountUnit.btc,
  bool masked = false,
  Map<String, String> names = const {'w1': 'Cold storage'},
}) {
  return NewTxAnnouncer.compose(
    claimed(reports),
    walletNames: names,
    unit: unit,
    masked: masked,
  ).map((notice) => notice.body).toList();
}

Widget settingsApp(FakeBridge bridge, FakeNotifications service) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      notificationServiceProvider.overrideWithValue(service),
      backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
      livePlatformProvider.overrideWithValue(FakeLivePlatform()),
    ],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const SettingsScreen(section: SettingsSection.notifications),
    ),
  );
}

void main() {
  group('what a notification says', () {
    test('a receipt states the amount, an exit states it too', () {
      expect(
        bodies([
          report([tx(1000000)]),
        ]),
        ['Received ${formatAmount(1000000, AmountUnit.btc)} · confirmed'],
      );
      expect(
        bodies([
          report([tx(-200000)]),
        ]),
        [
          '${formatAmount(200000, AmountUnit.btc)} left this wallet · '
              'confirmed',
        ],
      );
    });

    test('an unconfirmed transaction says it is pending', () {
      expect(
        bodies([
          report([tx(1000, confirmed: false)]),
        ]),
        ['Received ${formatAmount(1000, AmountUnit.btc)} · pending'],
      );
    });

    test('the display unit is the one on screen', () {
      expect(
        bodies([
          report([tx(1000000)]),
        ], unit: AmountUnit.sats),
        ['Received ${formatAmount(1000000, AmountUnit.sats)} · confirmed'],
      );
    });

    test('masked balances keep the amount out of the notification', () {
      expect(
        bodies([
          report([tx(1000000)]),
        ], masked: true),
        ['New transaction · confirmed'],
      );
      expect(
        bodies([
          report([tx(-1000000)]),
        ], masked: true),
        ['New outgoing transaction · confirmed'],
      );
    });

    test('past three, the rest are counted in one line', () {
      final many = [
        for (var i = 0; i < 5; i++) tx(1000 * (i + 1), txid: 'tx$i'),
      ];
      final said = bodies([report(many)]);
      expect(said, hasLength(noticesPerWallet + 1));
      expect(said.last, '2 more new transactions');
    });

    test('the wallet name is the title, its id the fallback', () {
      final notices = NewTxAnnouncer.compose(
        claimed([
          report([tx(1000)]),
          report([tx(2000, txid: 'b')], id: 'w2'),
        ]),
        walletNames: const {'w1': 'Cold storage'},
        unit: AmountUnit.btc,
        masked: false,
      );
      expect(notices.map((n) => n.title), ['Cold storage', 'w2']);
    });

    test('the same transaction always gets the same id', () {
      expect(noticeId('abc'), noticeId('abc'));
      expect(noticeId('abc'), isNot(noticeId('abd')));
      expect(noticeId('abc'), greaterThanOrEqualTo(0));
    });
  });

  group('a sync says what it found', () {
    ProviderContainer container(FakeBridge bridge, FakeNotifications service) {
      final made = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          notificationServiceProvider.overrideWithValue(service),
          backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
          livePlatformProvider.overrideWithValue(FakeLivePlatform()),
        ],
      );
      addTearDown(made.dispose);
      return made;
    }

    test('nothing is posted while the notice is off', () async {
      final service = FakeNotifications();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      bridge.onSyncWallet = (id) => report([tx(1000)], id: id);
      final made = container(bridge, service);

      await made.read(syncProvider.notifier).syncWallet('w1');
      expect(service.posted, isEmpty);
    });

    test('the first sync of a wallet is not announced', () async {
      // A wallet seen for the first time hands over its whole history
      // as new: telling someone about a payment from three years ago
      // is noise, and a restore would be a burst of it.
      final service = FakeNotifications();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      bridge.onSyncWallet = (id) =>
          report([tx(1000, txid: 'a'), tx(2000, txid: 'b')], id: id);
      final made = container(bridge, service);
      await made.read(notifyNewTxProvider.notifier).set(true);

      await made.read(syncProvider.notifier).syncWallet('w1');
      expect(service.posted, isEmpty);
    });

    test('with the notice on, one line per transaction', () async {
      final service = FakeNotifications();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      var round = 0;
      bridge.onSyncWallet = (id) =>
          report([tx(1000, txid: 'tx${round++}')], id: id);
      final made = container(bridge, service);
      await made.read(notifyNewTxProvider.notifier).set(true);

      // The first sync settles what the wallet already held; what the
      // next one finds is genuinely new.
      await made.read(syncProvider.notifier).syncWallet('w1');
      await made.read(syncProvider.notifier).syncWallet('w1');
      expect(service.posted, hasLength(1));
      expect(service.posted.single.title, 'Cold storage');
      expect(
        service.posted.single.body,
        'Received ${formatAmount(1000, AmountUnit.btc)} · confirmed',
      );
    });

    test('a sync that found nothing says nothing', () async {
      final service = FakeNotifications();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      bridge.onSyncWallet = (id) => report(const [], id: id);
      final made = container(bridge, service);
      await made.read(notifyNewTxProvider.notifier).set(true);

      await made.read(syncProvider.notifier).syncWallet('w1');
      expect(service.posted, isEmpty);
    });

    test('a refused permission leaves the notice off', () async {
      final service = FakeNotifications(granted: false);
      final bridge = FakeBridge(wallets: [makeMeta()]);
      final made = container(bridge, service);

      await made.read(notifyNewTxProvider.notifier).set(true);
      expect(made.read(notifyNewTxProvider), isFalse);
      expect(made.read(notificationsRefusedProvider), isTrue);
      expect(service.permissionAsks, 1);
    });
  });

  group('the settings card', () {
    testWidgets('turning the notice on persists it and asks the system', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = FakeNotifications();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(settingsApp(bridge, service));
      await tester.pumpAndSettle();

      Future<void> pickQuarterHour() async {
        await tester.tap(find.byType(GerfautSelect<BackgroundCheck>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Every 15 min').last);
        await tester.pumpAndSettle();
      }

      // The cadence means nothing until something is said: the option
      // is there, and does not take the tap.
      await pickQuarterHour();
      expect(bridge.appPrefs['notify.background'], isNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(NotificationsSection),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.permissionAsks, 1);
      expect(bridge.appPrefs['notify.new_tx'], '1');

      await pickQuarterHour();
      expect(bridge.appPrefs['notify.background'], '900');
    });

    testWidgets('a refused system permission is stated, not hidden', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = FakeNotifications(granted: false);
      await tester.pumpWidget(
        settingsApp(FakeBridge(wallets: [makeMeta()]), service),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(NotificationsSection),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Notifications are off for Gerfaut in the system settings.'),
        findsOneWidget,
      );
    });
  });
}
