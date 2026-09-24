import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/bridge.dart';
import '../../src/format.dart';
import '../../src/models.dart';
import '../../src/premium.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notice.dart';
import '../../widgets/overflow_menu.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_pill.dart';
import '../confirm_identity.dart';
import 'premium_error_note.dart';

/// What the Devices card can be asked to do about one device.
enum DeviceAction {
  approve(
    'Approve only a device you just connected yourself. Once approved, it '
        'sees your watched wallets, channels and alerts, and can change them.',
    'Approve',
    'Approving…',
  ),
  refuse(
    'Refuse this device? It is disconnected at once and sees nothing. If '
        'you did not connect it, someone has your key: change it in Licence '
        'above.',
    'Refuse',
    'Refusing…',
  ),
  disconnect(
    'Disconnect this device? It loses access at once. To use Premium there '
        'again, enter the key on it and approve it here.',
    'Disconnect',
    'Disconnecting…',
  );

  const DeviceAction(this.question, this.label, this.busyLabel);

  /// What the question under the row says.
  final String question;

  /// The button that answers yes.
  final String label;

  /// The same button while the server is asked.
  final String busyLabel;
}

/// The glyph of a device's kind: a phone, a laptop, a screen.
IconData deviceGlyph(DevicePlatform? platform) => switch (platform) {
  DevicePlatform.android || DevicePlatform.ios => LucideIcons.smartphone,
  DevicePlatform.macos => LucideIcons.laptop,
  DevicePlatform.windows || DevicePlatform.linux || null => LucideIcons.monitor,
};

/// Every device that entered the key, and what to do about each: a new
/// one waits with Refuse and Approve on its row, one with access can be
/// disconnected from its menu. Each answer is asked under its row first,
/// then the owner proves who they are, then the server is told.
///
/// Right after the licence, and only on a device with full access: one
/// that waits sees nothing of the others.
class DevicesCard extends ConsumerStatefulWidget {
  const DevicesCard({super.key});

  @override
  ConsumerState<DevicesCard> createState() => _DevicesCardState();
}

class _DevicesCardState extends ConsumerState<DevicesCard> {
  /// The row whose question is up, and which question.
  ({String id, DeviceAction action})? _asking;

  /// The device a call is out about.
  String? _busyId;

  /// The owner is being asked who they are.
  bool _verifying = false;
  BridgeException? _error;

  @override
  void initState() {
    super.initState();
    // The list is read again whenever the card comes on screen: a device
    // may have connected since the last look, and whoever opens this
    // page opens it to see who is there now. The last list stands in
    // meanwhile.
    Future.microtask(() {
      if (mounted) ref.invalidate(premiumDevicesProvider);
    });
  }

  /// What a benign confirmation says once the server has done it.
  static String _done(DeviceAction action) => switch (action) {
    DeviceAction.approve => 'Device approved',
    DeviceAction.refuse => 'Device refused',
    DeviceAction.disconnect => 'Device disconnected',
  };

  void _ask(PremiumDevice device, DeviceAction action) {
    if (_busyId != null || _verifying) return;
    setState(() {
      _asking = (id: device.id, action: action);
      _error = null;
    });
  }

  void _cancel() => setState(() => _asking = null);

  /// The yes: who holds the phone first, then the server. The question
  /// stays up until the server has answered, its buttons held, so a
  /// failure keeps the next try one tap away and a second tap lands on
  /// nothing.
  Future<void> _confirm(PremiumDevice device, DeviceAction action) async {
    if (_busyId != null || _verifying) return;
    setState(() => _verifying = true);
    final bool confirmed;
    try {
      confirmed = await confirmIdentity(context, ref);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
    if (!confirmed || !mounted) return;
    setState(() {
      _busyId = device.id;
      _error = null;
    });
    final bridge = ref.read(bridgeProvider);
    try {
      switch (action) {
        case DeviceAction.approve:
          await bridge.premiumApproveDevice(device.id);
        case DeviceAction.refuse:
        case DeviceAction.disconnect:
          await bridge.premiumRemoveDevice(device.id);
      }
      if (!mounted) return;
      setState(() => _asking = null);
      // The row itself says what changed; the toast only confirms it.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_done(action))));
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
        // Read again either way: a device refused elsewhere meanwhile is
        // gone, one approved elsewhere has its access.
        ref.invalidate(premiumDevicesProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final muted = tokens.bodySmall.copyWith(color: tokens.textMuted);
    final devices = ref.watch(premiumDevicesProvider);
    // Only a list read with this connection: one from before the key was
    // changed, or from another key, reads as loading meanwhile.
    final list = ref.watch(accountDevicesProvider);
    final readError = devices.hasError && !devices.isLoading
        ? devices.error
        : null;
    final error =
        _error ??
        switch (readError) {
          null => null,
          final BridgeException bridge => bridge,
          final other => BridgeException('internal', '$other'),
        };
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          icon: LucideIcons.monitorSmartphone,
          iconColor: tokens.premium,
          title: 'Devices',
          children: [
            Text(
              'Every device that entered your key. A new one waits 10 days, '
              'or until you approve it here.',
              style: muted,
            ),
            const SizedBox(height: GerfautSpacing.sm),
            if (list == null && readError != null)
              Text('The server could not be asked.', style: muted)
            else if (list == null)
              Text('Loading…', style: muted)
            else
              for (final (index, device) in list.indexed) ...[
                if (index > 0)
                  Divider(height: 1, thickness: 1, color: tokens.border),
                _DeviceRow(
                  device: device,
                  nowUnix: now,
                  asking: _asking?.id == device.id ? _asking!.action : null,
                  busy: _busyId == device.id,
                  holding: _verifying || (_busyId != null),
                  onAsk: (action) => _ask(device, action),
                  onConfirm: (action) => _confirm(device, action),
                  onCancel: _cancel,
                ),
              ],
          ],
        ),
        if (error != null)
          PremiumErrorNote(
            error: error,
            onRetry: () {
              setState(() => _error = null);
              ref.invalidate(premiumDevicesProvider);
            },
          ),
      ],
    );
  }
}

/// One device: its glyph, its kind, when it connected, whether it is
/// this one, and its access; the answers it needs under it.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.nowUnix,
    required this.asking,
    required this.busy,
    required this.holding,
    required this.onAsk,
    required this.onConfirm,
    required this.onCancel,
  });

  final PremiumDevice device;
  final int nowUnix;

  /// The question up under this row, if any.
  final DeviceAction? asking;

  /// The server is being asked about this device.
  final bool busy;

  /// Something on the card is under way: no new question, no answer.
  final bool holding;
  final ValueChanged<DeviceAction> onAsk;
  final ValueChanged<DeviceAction> onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final waiting = !device.fullAccess;
    final asking = this.asking;
    // Another device with access can be let go from here; this one
    // leaves by forgetting its key, and a waiting one has its answers
    // on the row.
    final canDisconnect = !waiting && !device.thisDevice;
    final info = MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: GerfautSpacing.sm,
            runSpacing: GerfautSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                device.label,
                style: tokens.bodySmall.copyWith(
                  color: tokens.text,
                  fontWeight: FontWeight.w500,
                  fontVariations: const [FontVariation('wght', 500)],
                ),
              ),
              if (device.thisDevice)
                const StatusPill.tone(
                  tone: PillTone.neutral,
                  icon: LucideIcons.user,
                  label: 'This device',
                ),
            ],
          ),
          Text(
            'Connected ${formatDayMonthYear(device.connectedAt)}',
            style: tokens.label.copyWith(
              letterSpacing: 0,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: GerfautSpacing.xs),
          waiting
              ? StatusPill.tone(
                  tone: PillTone.pending,
                  icon: LucideIcons.clock,
                  label: waitingLabel(device, nowUnix: nowUnix),
                )
              : const StatusPill.tone(
                  tone: PillTone.neutral,
                  icon: LucideIcons.shieldCheck,
                  label: 'Full access',
                ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  deviceGlyph(device.platform),
                  size: 16,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(width: GerfautSpacing.sm + GerfautSpacing.xs),
              Expanded(child: info),
              if (canDisconnect)
                OverflowMenu(
                  tooltip: 'More for ${device.label}',
                  items: [
                    OverflowMenuItem(
                      icon: LucideIcons.unplug,
                      label: 'Disconnect',
                      onSelected: holding
                          ? () {}
                          : () => onAsk(DeviceAction.disconnect),
                    ),
                  ],
                ),
            ],
          ),
          if (asking != null)
            Padding(
              padding: const EdgeInsets.only(top: GerfautSpacing.sm),
              child: GerfautNotice(
                tone: NoticeTone.info,
                liveRegion: true,
                message: asking.question,
                actionsBelow: true,
                action: ConfirmActions(
                  cancel: GhostButton(
                    label: 'Cancel',
                    onPressed: busy || holding ? null : onCancel,
                  ),
                  confirm: switch (asking) {
                    DeviceAction.approve => PremiumButton(
                      label: busy ? asking.busyLabel : asking.label,
                      onPressed: busy || holding
                          ? null
                          : () => onConfirm(asking),
                    ),
                    _ => DangerButton(
                      label: busy ? asking.busyLabel : asking.label,
                      onPressed: busy || holding
                          ? null
                          : () => onConfirm(asking),
                    ),
                  },
                ),
              ),
            )
          else if (waiting && !device.thisDevice)
            Padding(
              padding: const EdgeInsets.only(top: GerfautSpacing.sm),
              child: ConfirmActions(
                cancel: DangerButton(
                  label: 'Refuse',
                  onPressed: holding ? null : () => onAsk(DeviceAction.refuse),
                ),
                confirm: PremiumButton(
                  label: 'Approve',
                  onPressed: holding ? null : () => onAsk(DeviceAction.approve),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
