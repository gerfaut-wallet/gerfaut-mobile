import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/apps.dart';
import '../src/bridge.dart';
import '../src/clipboard.dart';
import '../src/models.dart';
import '../src/premium.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/app_bar.dart';
import '../widgets/buttons.dart';
import '../widgets/notice.dart';
import '../widgets/password_field.dart';
import '../widgets/pinned_action_form.dart';
import '../widgets/status_pill.dart';
import 'settings/fields.dart';

/// The Lucide glyph of a channel kind, the same on every surface.
IconData channelGlyph(ChannelKind kind) => switch (kind) {
  ChannelKind.ntfy => LucideIcons.bell,
  ChannelKind.telegram => LucideIcons.send,
  ChannelKind.email => LucideIcons.mail,
  ChannelKind.webhook => LucideIcons.webhook,
};

/// One line on what each kind is, under its name in the picker.
String channelHint(ChannelKind kind) => switch (kind) {
  ChannelKind.ntfy => 'Push to the ntfy app, on a topic only you know.',
  ChannelKind.telegram => 'Messages from the Gerfaut bot.',
  ChannelKind.email => 'A short e-mail per alert.',
  ChannelKind.webhook => 'A signed POST to a server of yours.',
};

/// The `ntfy://` form of a subscribe URL: what opens the ntfy app on
/// the topic, subscription offered.
String ntfyAppUrl(String subscribeUrl) =>
    subscribeUrl.replaceFirst(RegExp(r'^https?://'), 'ntfy://');

/// The app a subscribe link is handed to, and no other. The scheme is
/// anyone's to declare; the package is one app.
const String ntfyPackage = 'io.heckel.ntfy';

/// Opens a link in the app that claims it, or the browser.
Future<bool> openExternal(String url) {
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Offers the four kinds, each with its line of explanation, from the
/// bottom of the screen. Answers the kind picked, or null.
Future<ChannelKind?> showAddChannelSheet(BuildContext context) {
  final tokens = Theme.of(context).extension<GerfautTokens>()!;
  return showModalBottomSheet<ChannelKind>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: GerfautSpacing.sm,
            bottom: GerfautSpacing.xs,
          ),
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: tokens.border,
              borderRadius: BorderRadius.circular(GerfautRadius.full),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GerfautSpacing.md,
            GerfautSpacing.sm,
            GerfautSpacing.md,
            GerfautSpacing.xs,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'ADD A CHANNEL',
              style: tokens.label.copyWith(color: tokens.textMuted),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GerfautSpacing.sm + 2,
            0,
            GerfautSpacing.sm + 2,
            GerfautSpacing.md,
          ),
          child: Column(
            children: [
              for (final kind in ChannelKind.values)
                _KindRow(
                  kind: kind,
                  onTap: () => Navigator.of(sheetContext).pop(kind),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One kind to pick: the glyph, the name, and the line under it. The
/// row of every floating list in the app: 44px at least, radius 8.
class _KindRow extends StatelessWidget {
  const _KindRow({required this.kind, required this.onTap});

  final ChannelKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Semantics(
      button: true,
      label: '${kind.label}: ${channelHint(kind)}',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: GerfautSpacing.sm + 2,
            vertical: GerfautSpacing.sm - 2,
          ),
          child: Row(
            children: [
              Icon(channelGlyph(kind), size: 16, color: tokens.text),
              const SizedBox(width: GerfautSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kind.label,
                      style: tokens.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        fontVariations: const [FontVariation('wght', 500)],
                      ),
                    ),
                    Text(
                      channelHint(kind),
                      style: tokens.label.copyWith(
                        fontSize: 11,
                        letterSpacing: 0,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page under a created ntfy channel: the topic to subscribe to,
/// copied or opened in the ntfy app. The topic is the whole secret of
/// the channel, so it is shown in full, in mono, and nowhere else.
class NtfyChannelScreen extends ConsumerStatefulWidget {
  const NtfyChannelScreen({super.key, required this.subscribeUrl});

  /// `https://ntfy.gerfaut-wallet.com/<topic>`.
  final String subscribeUrl;

  @override
  ConsumerState<NtfyChannelScreen> createState() => _NtfyChannelScreenState();
}

class _NtfyChannelScreenState extends ConsumerState<NtfyChannelScreen> {
  bool _noApp = false;

  Future<void> _copy() async {
    // The topic is the whole secret of the channel: anyone holding it
    // subscribes to the alerts of this account. It does not belong in
    // the system's clipboard preview or its history.
    await ref.read(sensitiveClipboardProvider).copy(widget.subscribeUrl);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Future<void> _openApp() async {
    // To ntfy by name. Opened the ordinary way the link would be
    // offered to every app that declared the scheme, and the topic in
    // it is the whole secret of this channel. Nothing opened means the
    // app is not on this phone, which is what the note below says.
    //
    // And only ever an ntfy link: the URL comes from the server, and a
    // scheme this page did not build has no business being started by
    // name, whatever the package.
    final url = ntfyAppUrl(widget.subscribeUrl);
    final opened =
        url.startsWith('ntfy://') &&
        await ref
            .read(appOpenerProvider)
            .openIn(package: ntfyPackage, url: url);
    if (!opened && mounted) setState(() => _noApp = true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Scaffold(
      appBar: GerfautAppBar.text('ntfy'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: PinnedActionForm(
            action: PrimaryButton(
              label: 'Open in ntfy',
              icon: LucideIcons.externalLink,
              expand: true,
              onPressed: _openApp,
            ),

            children: [
              Text(
                'Subscribe to this topic in the ntfy app',
                style: tokens.body,
              ),
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                'Alerts for your watched wallets will arrive on it. Only '
                'someone who knows the topic can read them: keep it to '
                'yourself.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(GerfautSpacing.md),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(GerfautRadius.lg),
                  border: Border.all(color: tokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOPIC URL',
                      style: tokens.label.copyWith(color: tokens.textMuted),
                    ),
                    const SizedBox(height: GerfautSpacing.sm),
                    SelectableText(
                      widget.subscribeUrl,
                      style: tokens.data.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: GerfautSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GhostButton(
                        label: 'Copy',
                        icon: LucideIcons.copy,
                        onPressed: _copy,
                      ),
                    ),
                  ],
                ),
              ),
              if (_noApp) ...[
                const SizedBox(height: GerfautSpacing.md),
                const GerfautNotice(
                  tone: NoticeTone.info,
                  message: 'The ntfy app is not installed on this phone.',
                  hint:
                      'Install it from F-Droid or the Play Store, then open '
                      'this link again, or paste the URL into it.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The page under a Telegram channel until the bot hears from it: the
/// code to send, the link that sends it, and a watch on the server
/// that turns the page into "Linked" by itself.
class TelegramChannelScreen extends ConsumerStatefulWidget {
  const TelegramChannelScreen({
    super.key,
    required this.channelId,
    required this.code,
    required this.startUrl,
    this.pollEvery = const Duration(seconds: 3),
    this.pollFor = const Duration(minutes: 2),
  });

  final String channelId;

  /// The code the bot expects after `/start`.
  final String code;

  /// `https://t.me/<bot>?start=<code>`.
  final String startUrl;

  /// How often the server is asked, and for how long before the page
  /// hands the asking over to a button.
  final Duration pollEvery;
  final Duration pollFor;

  @override
  ConsumerState<TelegramChannelScreen> createState() =>
      _TelegramChannelScreenState();
}

class _TelegramChannelScreenState extends ConsumerState<TelegramChannelScreen> {
  Timer? _timer;
  bool _linked = false;
  bool _checking = false;
  bool _gaveUp = false;

  /// The hand refresh asked and the bot still had not answered: said
  /// under the button, or the tap looks like it did nothing.
  bool _notYet = false;

  /// The hand refresh could not ask: the server's refusal, under the
  /// button, where the poll's silence would have hidden it.
  BridgeException? _error;

  /// Ticks of the poll so far. The rest is measured in ticks, not on
  /// the clock: a tick that fires late still counts as one, and a test
  /// clock moves the count the same way the real one does.
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.pollEvery, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    _ticks += 1;
    if (widget.pollEvery * _ticks > widget.pollFor) {
      _timer?.cancel();
      if (mounted) setState(() => _gaveUp = true);
      return;
    }
    await _check();
  }

  /// Asks the server once. The poll asks quietly, since the next tick
  /// asks again and a page that flickers between answers says nothing
  /// useful; a tap on the button asks out loud, since the tap is the
  /// last tick and whatever it finds is the whole answer.
  Future<void> _check({bool byHand = false}) async {
    if (_checking || _linked) return;
    setState(() {
      _checking = true;
      _notYet = false;
      _error = null;
    });
    try {
      final channels = await ref.read(bridgeProvider).premiumChannels();
      final mine = channels.where((c) => c.id == widget.channelId);
      if (!mounted) return;
      if (mine.isNotEmpty && mine.first.linked) {
        _timer?.cancel();
        setState(() => _linked = true);
        ref.invalidate(premiumChannelsProvider);
      } else if (byHand) {
        setState(() => _notYet = true);
      }
    } on BridgeException catch (error) {
      if (byHand && mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Scaffold(
      appBar: GerfautAppBar.text('Telegram'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: PinnedActionForm(
            action: _linked
                ? PrimaryButton(
                    label: 'Done',
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : PrimaryButton(
                    label: 'Open Telegram',
                    icon: LucideIcons.externalLink,
                    expand: true,
                    onPressed: () => openExternal(widget.startUrl),
                  ),

            children: [
              if (_linked) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text('Telegram is linked', style: tokens.body),
                    ),
                    const StatusPill.tone(
                      tone: PillTone.neutral,
                      icon: LucideIcons.link,
                      label: 'Linked',
                    ),
                  ],
                ),
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  'Alerts for your watched wallets will arrive from the bot.',
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
              ] else ...[
                Text(
                  'Send this to @${_bot(widget.startUrl)}',
                  style: tokens.body,
                ),
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  'Open Telegram and press Start: the code is sent for you. '
                  'This page follows along and says when the bot has it.',
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: GerfautSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(GerfautSpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(GerfautRadius.lg),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LINK CODE',
                        style: tokens.label.copyWith(color: tokens.textMuted),
                      ),
                      const SizedBox(height: GerfautSpacing.sm),
                      SelectableText(
                        '/start ${widget.code}',
                        style: tokens.data.copyWith(fontSize: 22, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: GerfautSpacing.md),
                // The page follows along for two minutes, then hands
                // the asking to a button: a poll that never ends is a
                // call every few seconds for as long as the page is
                // left open. A Wrap, so the button goes under the pill
                // at a large text size rather than past the edge.
                Wrap(
                  spacing: GerfautSpacing.sm,
                  runSpacing: GerfautSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const StatusPill.tone(
                      tone: PillTone.pending,
                      icon: LucideIcons.clock,
                      label: 'Waiting for the bot',
                    ),
                    if (_gaveUp)
                      GhostButton(
                        label: _checking ? 'Checking…' : 'Check again',
                        icon: LucideIcons.refreshCw,
                        onPressed: _checking
                            ? null
                            : () => _check(byHand: true),
                      ),
                  ],
                ),
                if (_notYet) ...[
                  const SizedBox(height: GerfautSpacing.sm),
                  Text(
                    'The bot has not heard from you yet. Send the code, '
                    'then check again.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: GerfautSpacing.sm),
                  _CheckFailed(error: _error!),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The bot's name out of its link, `t.me/<bot>?start=…`.
  static String _bot(String url) {
    final path = Uri.tryParse(url)?.pathSegments;
    return path == null || path.isEmpty ? 'GerfautAlertsBot' : path.first;
  }
}

/// A hand refresh the server did not answer, in the words the premium
/// cards use for the same failure, under the button that asked.
class _CheckFailed extends StatelessWidget {
  const _CheckFailed({required this.error});

  final BridgeException error;

  @override
  Widget build(BuildContext context) {
    final failure = premiumFailure(error);
    return GerfautNotice(
      tone: NoticeTone.info,
      message: failure.message,
      hint: failure.hint,
      detail: failure.detail,
      liveRegion: true,
    );
  }
}

/// A field and one hint: the page that adds an e-mail channel. Answers
/// the created channel, or null when left.
class EmailChannelScreen extends ConsumerStatefulWidget {
  const EmailChannelScreen({super.key});

  @override
  ConsumerState<EmailChannelScreen> createState() => _EmailChannelScreenState();
}

class _EmailChannelScreenState extends ConsumerState<EmailChannelScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  BridgeException? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _wellFormed {
    final text = _controller.text.trim();
    final at = text.indexOf('@');
    return at > 0 && at < text.length - 1 && !text.contains(' ');
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(bridgeProvider)
          .premiumCreateChannel(
            ChannelKind.email,
            target: _controller.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(created);
    } on BridgeException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
    }
  }

  /// What went wrong, in words fit for this page.
  ///
  /// Adding an address makes the server send one e-mail to it, and a
  /// mail that does not go out reaches the core as the server being
  /// out of reach — it is not, it answered to say the mail failed, and
  /// the status it carries is the only sign of the difference. Saying
  /// "the server did not take this address" of an address the server
  /// did take sends the person to correct what is already right, so
  /// that line is kept for a refusal and nothing else.

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final error = _error;
    final problem = error == null
        ? null
        : premiumFailure(
            error,
            refusal: 'The server did not take this address.',
          );
    return Scaffold(
      appBar: GerfautAppBar.text('E-mail'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: PinnedActionForm(
            action: PrimaryButton(
              label: _busy ? 'Adding…' : 'Add e-mail',
              expand: true,
              onPressed: _wellFormed && !_busy ? _add : null,
            ),

            children: [
              Text(
                'ADDRESS',
                style: tokens.label.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.sm),
              _EmailField(
                controller: _controller,
                onChanged: () => setState(() {}),
                onSubmitted: _wellFormed && !_busy ? _add : null,
              ),
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                'Alerts say which wallet moved, never an address or an amount.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              if (problem != null) ...[
                const SizedBox(height: GerfautSpacing.md),
                GerfautNotice(
                  tone: NoticeTone.info,
                  message: problem.message,
                  hint: problem.hint,
                  detail: problem.detail,
                  liveRegion: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The e-mail field: the address keyboard, no capitals, no suggestions,
/// the body size so the phone never zooms.
class _EmailField extends StatelessWidget {
  const _EmailField({
    required this.controller,
    required this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return TextField(
      controller: controller,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.emailAddress,
      textCapitalization: TextCapitalization.none,
      style: tokens.data.copyWith(fontSize: tokens.body.fontSize),
      onChanged: (_) => onChanged(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        hintText: 'you@example.org',
        hintStyle: tokens.data.copyWith(
          fontSize: tokens.body.fontSize,
          color: tokens.textMuted,
        ),
        filled: true,
        fillColor: tokens.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: GerfautSpacing.md,
          vertical: GerfautSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GerfautRadius.sm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GerfautRadius.sm),
          borderSide: BorderSide(color: tokens.primary, width: 2),
        ),
      ),
    );
  }
}

/// An `https://` URL and an optional secret: the page that adds a
/// webhook. Answers the created channel, or null when left.
class WebhookChannelScreen extends ConsumerStatefulWidget {
  const WebhookChannelScreen({super.key});

  @override
  ConsumerState<WebhookChannelScreen> createState() =>
      _WebhookChannelScreenState();
}

class _WebhookChannelScreenState extends ConsumerState<WebhookChannelScreen> {
  final _urlController = TextEditingController();
  final _secretController = TextEditingController();
  bool _busy = false;
  BridgeException? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  bool get _wellFormed {
    final uri = Uri.tryParse(_urlController.text.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final secret = _secretController.text;
    try {
      final created = await ref
          .read(bridgeProvider)
          .premiumCreateChannel(
            ChannelKind.webhook,
            target: _urlController.text.trim(),
            secret: secret.isEmpty ? null : secret,
          );
      if (mounted) Navigator.of(context).pop(created);
    } on BridgeException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final error = _error;
    final problem = error == null
        ? null
        : premiumFailure(
            error,
            refusal: 'The server did not take this webhook.',
          );
    return Scaffold(
      appBar: GerfautAppBar.text('Webhook'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: PinnedActionForm(
            action: PrimaryButton(
              label: _busy ? 'Adding…' : 'Add webhook',
              expand: true,
              onPressed: _wellFormed && !_busy ? _add : null,
            ),

            children: [
              Text(
                'URL',
                style: tokens.label.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.sm),
              MonoField(
                controller: _urlController,
                hint: 'https://example.org/gerfaut',
                onChanged: () => setState(() {}),
                tokens: tokens,
              ),
              const SizedBox(height: GerfautSpacing.md),
              PasswordField(
                label: 'Secret (optional)',
                controller: _secretController,
              ),
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                'Signed with HMAC-SHA256. See the docs.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              if (problem != null) ...[
                const SizedBox(height: GerfautSpacing.md),
                GerfautNotice(
                  tone: NoticeTone.info,
                  message: problem.message,
                  hint: problem.hint,
                  detail: problem.detail,
                  liveRegion: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
