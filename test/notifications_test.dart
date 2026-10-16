import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/live.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/notifications.dart';
import 'package:gerfaut/src/prefs.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/select_field.dart';
import 'package:gerfaut/widgets/setting_switch.dart';

import 'fakes.dart';

/// Records what would have been posted, and answers the permission the
/// way a test asks it to.
class FakeNotifications implements NotificationService {
  FakeNotifications({this.granted = true});

  bool granted;
  int inits = 0;
  int permissionAsks = 0;
  final List<({int id, String title, String body})> posted = [];

  /// What the system answers when asked whether notices get through.
  bool deliverableNow = true;

  @override
  Future<bool> deliverable() async => deliverableNow;

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

SyncReport report(List<NewTx> txs, {String id = 'w1'}) => SyncReport(
  walletId: id,
  newTxCount: txs.length,
  newTxs: txs,
  balance: makeBalance(0),
  tipHeight: 100,
  tookMs: 1,
  backend: 'mempool.space',
);

/// The switch of the new-transaction notice, the card's first.
final Finder newTransactionsSwitch = find.descendant(
  of: find.widgetWithText(SettingSwitch, 'New transactions'),
  matching: find.byType(Switch),
);

/// The switch that says whether a notification names the wallet and
/// the amount.
final Finder detailsSwitch = find.widgetWithText(
  SettingSwitch,
  'Show wallet and amount',
);

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
  group('what the core says is posted', () {
    const context = NoticeContext(
      names: {'w1': 'Cold storage'},
      unit: AmountUnit.btc,
      masked: false,
      details: true,
    );
    const arrival = LiveTx(
      walletId: 'w1',
      txid: 'a',
      netSats: 5000,
      stage: TxStage.mempool,
    );

    test('every notice the core composed, in its order', () async {
      final bridge = FakeBridge()
        ..onLiveNotices = (txs, context) => const [
          TxNotice(
            title: 'Cold storage',
            body: 'Received 0.00005000 BTC · pending',
            kind: NoticeKind.transaction,
            payment: (walletId: 'w1', txid: 'a'),
            walletId: 'w1',
          ),
          TxNotice(
            title: 'Cold storage',
            body: '4 more transactions',
            kind: NoticeKind.transaction,
            walletId: 'w1',
          ),
          TxNotice(
            title: 'Cold storage',
            body: '2 more pending payments are no longer coming',
            kind: NoticeKind.dropped,
            walletId: 'w1',
          ),
          TxNotice(
            title: 'Gerfaut',
            body: 'More transactions are coming in. Open Gerfaut to see them.',
            kind: NoticeKind.transaction,
          ),
        ];
      final service = FakeNotifications();
      await NewTxAnnouncer(service, bridge).announce(const [arrival], context);
      expect(bridge.noticeAsks.single.txs, const [arrival]);
      expect(bridge.noticeAsks.single.context, same(context));
      expect(service.posted.map((p) => (p.title, p.body)), [
        ('Cold storage', 'Received 0.00005000 BTC · pending'),
        ('Cold storage', '4 more transactions'),
        ('Cold storage', '2 more pending payments are no longer coming'),
        (
          'Gerfaut',
          'More transactions are coming in. Open Gerfaut to see them.',
        ),
      ]);
      // A payment keeps the id it had before the core wrote the words,
      // and so does the line that counts the rest of a wallet's sync:
      // what an earlier version posted is replaced, not stacked under.
      expect(service.posted.map((p) => p.id), [
        noticeId('w1:a'),
        noticeId('more:w1'),
        noticeId('gone:w1'),
        noticeId('waiting:transaction'),
      ]);
    });

    test('every notice of one payment takes the place of the last', () {
      TxNotice about(String walletId, String txid) => TxNotice(
        title: 't',
        body: 'b',
        kind: NoticeKind.transaction,
        payment: (walletId: walletId, txid: txid),
        walletId: walletId,
      );
      expect(postedId(about('w1', 'first')), postedId(about('w1', 'first')));
      // A payment between two watched wallets is said in each.
      expect(
        postedId(about('w1', 'move')),
        isNot(postedId(about('w2', 'move'))),
      );
      expect(postedId(about('w1', 'a')), isNot(postedId(about('w1', 'b'))));
    });

    test('a fee bump is posted under the payment it replaces', () async {
      final bridge = FakeBridge();
      final service = FakeNotifications();
      final announcer = NewTxAnnouncer(service, bridge);
      await announcer.announce(const [
        LiveTx(
          walletId: 'w1',
          txid: 'first',
          netSats: 50000,
          stage: TxStage.mempool,
        ),
      ], context);
      await announcer.announce(const [
        LiveTx(
          walletId: 'w1',
          txid: 'bump',
          netSats: 49600,
          stage: TxStage.confirmed,
          replaces: 'first',
        ),
      ], context);
      expect(service.posted[0].id, service.posted[1].id);
      // The core is handed the bump as it came, its first txid with it.
      expect(bridge.noticeAsks.last.txs.single.toJson(), {
        'wallet_id': 'w1',
        'txid': 'bump',
        'net_sats': 49600,
        'stage': 'confirmed',
        'replaces': 'first',
      });
    });

    test('nothing to say asks the core nothing', () async {
      final bridge = FakeBridge();
      final service = FakeNotifications();
      await NewTxAnnouncer(service, bridge).announce(const [], context);
      expect(bridge.noticeAsks, isEmpty);
      expect(service.posted, isEmpty);
    });

    test('the notices and the context read as the core writes them', () {
      final notice = TxNotice.fromJson(const {
        'title': 'Cold storage',
        'body': 'A pending payment of 0.00000001 BTC is no longer coming',
        'kind': 'dropped',
        'id': {'wallet_id': 'w1', 'txid': 'a'},
        'wallet_id': 'w1',
      });
      expect(notice.title, 'Cold storage');
      expect(notice.kind, NoticeKind.dropped);
      expect(notice.payment, (walletId: 'w1', txid: 'a'));
      expect(notice.walletId, 'w1');
      final flood = TxNotice.fromJson(const {
        'title': 'Gerfaut',
        'body': 'More transactions are coming in. Open Gerfaut to see them.',
        'kind': 'transaction',
        'id': null,
        'wallet_id': null,
      });
      expect(flood.payment, isNull);
      expect(flood.walletId, isNull);
      expect(
        const NoticeContext(
          names: {'w1': 'Cold storage'},
          unit: AmountUnit.sats,
          masked: true,
          details: false,
        ).toJson(),
        {
          'names': {'w1': 'Cold storage'},
          'unit': 'sats',
          'masked': true,
          'details': false,
        },
      );
    });

    test('the replaced txid is read from the core', () {
      final bump = LiveTx.fromJson(const {
        'wallet_id': 'w1',
        'txid': 'bump',
        'net_sats': 49600,
        'stage': 'confirmed',
        'replaces': 'first',
      });
      expect(bump.payment, 'first');
      final plain = LiveTx.fromJson(const {
        'wallet_id': 'w1',
        'txid': 'plain',
        'net_sats': 1000,
        'stage': 'mempool',
      });
      expect(plain.replaces, isNull);
      expect(plain.payment, 'plain');
      expect(plain.toJson().containsKey('replaces'), isFalse);
    });

    test('the same transaction always gets the same id', () {
      expect(noticeId('abc'), noticeId('abc'));
      expect(noticeId('abc'), isNot(noticeId('abd')));
      expect(noticeId('abc'), greaterThanOrEqualTo(0));
    });
  });

  group('what a background isolate claimed', () {
    /// The notice on unless said otherwise.
    final on = kPreferences.copyWith(notifyNewTx: true);
    FakeBridge vault(
      Preferences preferences, [
      Map<String, String> prefs = const {},
    ]) => FakeBridge(
      wallets: [makeMeta(id: 'w1', name: 'Savings')],
      settings: Settings(
        preferences: preferences,
        activeNetwork: Network.mainnet,
        backends: const {},
        appPrefs: prefs,
      ),
    );
    final claimed = [
      const LiveTx(
        walletId: 'w1',
        txid: 'aa',
        netSats: 150000,
        stage: TxStage.mempool,
      ),
    ];

    test('is said with the names and the unit the vault holds', () async {
      final notices = FakeNotifications();
      final bridge = vault(on.copyWith(unit: AmountUnit.sats));
      await announceFromVault(
        bridge,
        notices,
        claimed,
        isDisguised: () async => false,
      );
      final asked = bridge.noticeAsks.single;
      expect(asked.txs, claimed);
      expect(asked.context.names, {'w1': 'Savings'});
      expect(asked.context.unit, AmountUnit.sats);
      expect(asked.context.masked, isFalse);
      expect(notices.posted.single.title, 'Savings');
      expect(notices.posted.single.body, 'aa · pending');
    });

    test('names the wallet and the amount, app lock or not', () async {
      final bridge = vault(on)
        ..lock = const AppLock(kind: LockKind.pin, biometric: false);
      await announceFromVault(
        bridge,
        FakeNotifications(),
        claimed,
        isDisguised: () async => false,
      );
      expect(bridge.noticeAsks.single.context.details, isTrue);
      expect(bridge.noticeAsks.single.context.unit, AmountUnit.btc);
    });

    test('with the details off, asks for what happened alone', () async {
      final bridge = vault(on, {Pref.notifyDetails: '0'});
      await announceFromVault(
        bridge,
        FakeNotifications(),
        claimed,
        isDisguised: () async => false,
      );
      expect(bridge.noticeAsks.single.context.details, isFalse);
    });

    test('with the details on and amounts hidden, the name alone', () async {
      final bridge = vault(on.copyWith(masked: true), {
        Pref.notifyDetails: '1',
      });
      await announceFromVault(
        bridge,
        FakeNotifications(),
        claimed,
        isDisguised: () async => false,
      );
      expect(bridge.noticeAsks.single.context.details, isTrue);
      expect(bridge.noticeAsks.single.context.masked, isTrue);
    });

    test('is not said while the notice is off or the app disguised', () async {
      final notices = FakeNotifications();
      final off = vault(kPreferences);
      await announceFromVault(
        off,
        notices,
        claimed,
        isDisguised: () async => false,
      );
      final disguised = vault(on);
      await announceFromVault(
        disguised,
        notices,
        claimed,
        isDisguised: () async => true,
      );
      // Disguised, the details off change nothing: still not a word.
      final generic = vault(on, {Pref.notifyDetails: '0'});
      await announceFromVault(
        generic,
        notices,
        claimed,
        isDisguised: () async => true,
      );
      expect(notices.posted, isEmpty);
      // Nothing is composed either: the budget is not spent on silence.
      for (final bridge in [off, disguised, generic]) {
        expect(bridge.noticeAsks, isEmpty);
      }
    });
  });

  group('the choice of details', () {
    test('is on unless turned off, an older install included', () {
      expect(const AppPrefs({}).notifyDetails, isTrue);
      expect(const AppPrefs({Pref.notifyDetails: '1'}).notifyDetails, isTrue);
      expect(const AppPrefs({Pref.notifyDetails: '0'}).notifyDetails, isFalse);

      final made = ProviderContainer(
        overrides: [bridgeProvider.overrideWithValue(FakeBridge())],
      );
      addTearDown(made.dispose);
      expect(made.read(notifyDetailsProvider), isTrue);
      final notifier = made.read(notifyDetailsProvider.notifier);
      notifier.hydrate(null);
      expect(made.read(notifyDetailsProvider), isTrue);
      notifier.hydrate('0');
      expect(made.read(notifyDetailsProvider), isFalse);
      notifier.hydrate('1');
      expect(made.read(notifyDetailsProvider), isTrue);
    });

    test('is kept in the vault, where every isolate reads it', () async {
      final bridge = FakeBridge();
      final made = ProviderContainer(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
      );
      addTearDown(made.dispose);
      made.read(notifyDetailsProvider.notifier).set(false);
      await Future<void>.delayed(Duration.zero);
      expect(made.read(notifyDetailsProvider), isFalse);
      expect(bridge.appPrefs[Pref.notifyDetails], '0');
      made.read(notifyDetailsProvider.notifier).set(true);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.appPrefs[Pref.notifyDetails], '1');
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
      var round = 0;
      bridge.onSyncWallet = (id) =>
          report([tx(1000, txid: 'tx${round++}')], id: id);
      final made = container(bridge, service);

      await made.read(syncProvider.notifier).syncWallet('w1');
      await made.read(syncProvider.notifier).syncWallet('w1');
      expect(service.posted, isEmpty);
      expect(bridge.noticeAsks, isEmpty);
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
      expect(service.posted.single.body, 'tx1 · confirmed');
      final context = bridge.noticeAsks.single.context;
      expect(context.names, {'w1': 'Cold storage'});
      expect(context.unit, AmountUnit.btc);
      expect(context.masked, isFalse);
      expect(context.details, isTrue);
    });

    test('under an app lock, the open app still names the wallet', () async {
      final service = FakeNotifications();
      final bridge = FakeBridge(wallets: [makeMeta()])
        ..lock = const AppLock(kind: LockKind.pin, biometric: false);
      var round = 0;
      bridge.onSyncWallet = (id) =>
          report([tx(1000, txid: 'tx${round++}')], id: id);
      final made = container(bridge, service);
      await made.read(settingsProvider.future);
      await made.read(notifyNewTxProvider.notifier).set(true);

      await made.read(syncProvider.notifier).syncWallet('w1');
      await made.read(syncProvider.notifier).syncWallet('w1');
      expect(service.posted.single.title, 'Cold storage');
      expect(bridge.noticeAsks.single.context.details, isTrue);
    });

    test('with the details off, the open app names no wallet', () async {
      final service = FakeNotifications();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      var round = 0;
      bridge.onSyncWallet = (id) =>
          report([tx(1000, txid: 'tx${round++}')], id: id);
      final made = container(bridge, service);
      await made.read(notifyNewTxProvider.notifier).set(true);
      made.read(notifyDetailsProvider.notifier).set(false);

      await made.read(syncProvider.notifier).syncWallet('w1');
      await made.read(syncProvider.notifier).syncWallet('w1');
      expect(service.posted, hasLength(1));
      expect(bridge.noticeAsks.single.context.details, isFalse);
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

      await tester.tap(newTransactionsSwitch);
      await tester.pumpAndSettle();

      expect(service.permissionAsks, 1);
      expect(bridge.preferences.notifyNewTx, isTrue);

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

      await tester.tap(newTransactionsSwitch);
      await tester.pumpAndSettle();

      expect(
        find.text('Notifications are off for Gerfaut in the system settings.'),
        findsOneWidget,
      );
    });

    testWidgets('the details switch is on, and waits for the notice', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(settingsApp(bridge, FakeNotifications()));
      await tester.pumpAndSettle();

      // Notices off: drawn as chosen, on, and out of reach.
      SettingSwitch details() => tester.widget<SettingSwitch>(detailsSwitch);
      expect(details().value, isTrue);
      expect(details().onChanged, isNull);
      expect(
        tester
            .getSemantics(
              find.descendant(of: detailsSwitch, matching: find.byType(Switch)),
            )
            .label,
        'Show wallet and amount\nEven while Gerfaut is locked. Off, a '
        'notification only says that a transaction came in or went out.',
      );

      await tester.tap(newTransactionsSwitch);
      await tester.pumpAndSettle();
      expect(details().onChanged, isNotNull);

      await tester.tap(
        find.descendant(of: detailsSwitch, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();
      expect(details().value, isFalse);
      expect(bridge.appPrefs[Pref.notifyDetails], '0');
      handle.dispose();
    });
  });
}
