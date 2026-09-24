// What every Premium test starts from: a vault opened before, the fake
// server behind it, and the section or the whole app around them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/src/apps.dart';
import 'package:gerfaut/src/clipboard.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/identity.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/notifications.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';

import 'fakes.dart';

/// The key the fake server knows, as a person would type it.
const String knownKey = 'ABCD-EFGH-IJKM-NPQR';

/// A vault opened before, on mainnet, with a descriptor wallet and a
/// watched address.
FakeBridge premiumBridge({List<WalletMeta>? wallets, bool activated = false}) {
  final bridge = FakeBridge(
    wallets:
        wallets ??
        [
          makeMeta(id: 'w1', name: 'Cold storage'),
          makeMeta(
            id: 'w2',
            name: 'Donations',
            kind: const SingleAddressKind(address: 'bc1qdonations'),
          ),
          makeMeta(id: 'w3', name: 'Signet tests', network: Network.signet),
        ],
    settings: const Settings(
      activeNetwork: Network.mainnet,
      backends: {},
      appPrefs: {'onboarding.seen': '1'},
    ),
  );
  if (activated) {
    bridge.premiumKey = 'abcdefghijkmnpqr';
    bridge.premiumClaims = LicenceClaims(
      subject: 'ab' * 32,
      expiresAt: bridge.premiumPaidUntil,
      issuedAt: bridge.premiumPaidUntil - 60 * 86400,
    );
    // This phone connected first, and has full access since.
    bridge.premiumThisDeviceId = bridge.premiumAddDevice(
      platform: DevicePlatform.android,
      waiting: false,
      connectedAt: bridge.premiumNow - 30 * 86400,
    );
  }
  return bridge;
}

/// The settings opened on the Premium section, or on the root list.
Widget premiumApp(
  FakeBridge bridge, {
  bool root = false,
  FakeSensitiveClipboard? clipboard,
  FakeAppOpener? appOpener,
  FakeScreenLock? screenLock,
  FakeFingerprint? fingerprint,
  bool dark = false,
  SettingsSection section = SettingsSection.premium,
}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(FakeDisguise()),
      // The phone's own lock says yes unless a test says otherwise: the
      // prompt is the system's, and no test reaches it.
      screenLockGateProvider.overrideWithValue(screenLock ?? FakeScreenLock()),
      biometricGateProvider.overrideWithValue(
        fingerprint ?? FakeFingerprint(available: false),
      ),
      if (clipboard != null)
        sensitiveClipboardProvider.overrideWithValue(clipboard),
      if (appOpener != null) appOpenerProvider.overrideWithValue(appOpener),
    ],
    child: MaterialApp(
      theme: dark
          ? themeFrom(GerfautTokens.dark, Brightness.dark)
          : themeFrom(GerfautTokens.light, Brightness.light),
      home: SettingsScreen(section: root ? null : section),
    ),
  );
}

/// The whole app, the way it starts: the banner lives on the home screen.
Widget wholeApp(
  FakeBridge bridge, {
  RecordingNotifications? notifications,
  FakeDisguise? disguise,
}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(disguise ?? FakeDisguise()),
      screenLockGateProvider.overrideWithValue(FakeScreenLock()),
      biometricGateProvider.overrideWithValue(
        FakeFingerprint(available: false),
      ),
      notificationServiceProvider.overrideWithValue(
        notifications ?? RecordingNotifications(),
      ),
    ],
    child: const GerfautApp(),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
