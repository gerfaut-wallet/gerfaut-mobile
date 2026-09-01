import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/models.dart';
import '../src/policy_text.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/address_chip.dart';
import '../widgets/app_bar.dart';
import '../widgets/facts.dart';
import '../widgets/notice.dart';
import '../widgets/status_pill.dart';

/// What the descriptor says: who can spend, under which locks, and
/// whether each path is open right now. One page per wallet, a tap
/// from the balance, and the same page for every wallet: a single key
/// gets three lines, a watched address one sentence and its address.
///
/// Nothing here is a balance, so the masked mode has nothing to hide:
/// a policy is structure, and the coin counts are structure too.
class PolicyScreen extends ConsumerWidget {
  const PolicyScreen({super.key, required this.walletId});

  final String walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final name = ref.watch(snapshotProvider(walletId)).valueOrNull?.meta.name;
    final policy = ref.watch(policyProvider(walletId));

    return Scaffold(
      appBar: GerfautAppBar.text('Policy'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          children: [
            // The header carries the wallet's name: the bar says what the
            // page is, the body says whose policy it reads.
            if (name != null) ...[
              Text(
                name.toUpperCase(),
                style: tokens.label.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.sm),
            ],
            switch (policy) {
              AsyncData(:final value) => _Loaded(snapshot: value),
              AsyncError(:final error) => GerfautNotice(
                tone: NoticeTone.info,
                message: 'The policy could not be read.',
                detail: '$error',
              ),
              _ => const PolicyPlaceholder(),
            },
          ],
        ),
      ),
    );
  }
}

/// Two quiet blocks where the sentence and the first card will be: no
/// spinner, no shimmer, the shape of what is coming.
class PolicyPlaceholder extends StatelessWidget {
  const PolicyPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    Widget block({required double height, double? width}) => Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
      ),
    );
    return Semantics(
      label: 'Loading the policy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          block(height: 20, width: 240),
          const SizedBox(height: GerfautSpacing.lg),
          block(height: 140),
        ],
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.snapshot});

  final PolicySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final sentence = Text(describePolicy(snapshot), style: tokens.body);

    if (snapshot.kind == PolicyKind.address) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sentence,
          const SizedBox(height: GerfautSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: AddressChip(value: snapshot.descriptor, head: 10, tail: 8),
          ),
        ],
      );
    }

    // A single key has one path and it is open: a card would say the
    // sentence a second time. The page keeps to its three lines.
    final cards = snapshot.kind == PolicyKind.singleKey
        ? const <Widget>[]
        : [
            for (final branch in snapshot.branches)
              Padding(
                padding: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
                child: _BranchCard(branch: branch, snapshot: snapshot),
              ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sentence,
        const SizedBox(height: GerfautSpacing.lg),
        ...cards,
        if (snapshot.hasTimeBasedLocks) ...[
          // Said once, under the cards: every clock on this page is this
          // device's, and the chain's median time trails it.
          Text(
            "Time locks compare against this device's clock; "
            'the chain can lag by up to two hours.',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: GerfautSpacing.lg),
        ] else if (cards.isNotEmpty)
          const SizedBox(height: GerfautSpacing.sm + GerfautSpacing.xs),
        _KeysSection(keys: snapshot.keys),
        const SizedBox(height: GerfautSpacing.lg),
        _DescriptorSection(
          descriptor: snapshot.descriptor,
          policy: snapshot.policy,
        ),
      ],
    );
  }
}

/// One way to spend: its role, its condition in words, the keys it
/// names, its locks one a line, and where it stands.
class _BranchCard extends StatelessWidget {
  const _BranchCard({required this.branch, required this.snapshot});

  final PolicyBranch branch;
  final PolicySnapshot snapshot;

  /// The keys the condition names, in order of first mention.
  List<PolicyKey> _keysOf(PolicyCondition condition) {
    final ids = <String>{};
    void walk(PolicyCondition c) {
      switch (c) {
        case KeyCondition(:final keyId):
          ids.add(keyId);
        case ThreshCondition(:final items):
          items.forEach(walk);
        case AfterCondition() || OlderCondition() || PreimageCondition():
          break;
      }
    }

    walk(condition);
    return [for (final id in ids) ?snapshot.keyById(id)];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final keys = _keysOf(branch.condition);
    final status = describeBranchState(branch);
    final date = status.date;
    final progress = status.progress;

    return Container(
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
          FieldLabel(branch.label, tokens: tokens),
          const SizedBox(height: GerfautSpacing.sm),
          _ConditionText(
            line: describeCondition(branch.condition, snapshot),
            tokens: tokens,
          ),
          if (keys.isNotEmpty) ...[
            const SizedBox(height: GerfautSpacing.sm + GerfautSpacing.xs),
            Wrap(
              spacing: GerfautSpacing.sm,
              runSpacing: GerfautSpacing.sm,
              children: [for (final key in keys) _KeyPill(policyKey: key)],
            ),
          ],
          if (branch.timelocks.isNotEmpty) ...[
            const SizedBox(height: GerfautSpacing.sm + GerfautSpacing.xs),
            for (final lock in branch.timelocks)
              Padding(
                padding: const EdgeInsets.only(bottom: GerfautSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FirstLine(
                      style: tokens.bodySmall,
                      child: Icon(
                        LucideIcons.clock,
                        size: 14,
                        color: tokens.textMuted,
                        semanticLabel: 'Timelock',
                      ),
                    ),
                    const SizedBox(width: GerfautSpacing.sm),
                    Expanded(
                      child: Text(
                        describeTimelock(lock),
                        style: tokens.bodySmall.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: GerfautSpacing.sm + GerfautSpacing.xs),
          _StatePill(status: status),
          if (date != null) ...[
            const SizedBox(height: GerfautSpacing.xs + 2),
            Text(
              'Around $date',
              style: tokens.label.copyWith(color: tokens.textMuted),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: GerfautSpacing.sm),
            LockProgress(progress: progress),
          ],
        ],
      ),
    );
  }
}

/// The condition as a phrase; a nested threshold puts its parts on
/// their own lines, one level in.
class _ConditionText extends StatelessWidget {
  const _ConditionText({
    required this.line,
    required this.tokens,
    this.depth = 0,
  });

  final ConditionLine line;
  final GerfautTokens tokens;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.text,
          style: depth == 0
              ? tokens.body
              : tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
        for (final child in line.children)
          Padding(
            padding: const EdgeInsets.only(
              left: GerfautSpacing.md,
              top: GerfautSpacing.xs,
            ),
            child: _ConditionText(
              line: child,
              tokens: tokens,
              depth: depth + 1,
            ),
          ),
      ],
    );
  }
}

/// A key as a neutral chip: its label, then its fingerprint in the
/// data face. No colour: a key is not a state.
class _KeyPill extends StatelessWidget {
  const _KeyPill({required this.policyKey});

  final PolicyKey policyKey;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final fingerprint = policyKey.fingerprint;
    return Semantics(
      label: fingerprint == null
          ? policyKey.label
          : '${policyKey.label}, fingerprint $fingerprint',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: GerfautSpacing.sm + 2,
          vertical: GerfautSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceSunken,
          borderRadius: BorderRadius.circular(GerfautRadius.full),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              policyKey.label,
              style: tokens.label.copyWith(color: tokens.text),
            ),
            if (fingerprint != null) ...[
              const SizedBox(width: GerfautSpacing.sm),
              Text(
                fingerprint,
                style: tokens.data.copyWith(
                  fontSize: 11,
                  color: tokens.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The state pill of a branch, its tone mapped to the system's three:
/// Lichen with a check when open, Ambre with a clock within thirty
/// days, neutral otherwise.
class _StatePill extends StatelessWidget {
  const _StatePill({required this.status});

  final BranchStatus status;

  @override
  Widget build(BuildContext context) {
    final (PillTone tone, IconData icon) = switch (status.tone) {
      StateTone.open => (PillTone.confirmed, LucideIcons.check),
      StateTone.soon => (PillTone.pending, LucideIcons.clock),
      StateTone.far => (PillTone.neutral, LucideIcons.clock),
      StateTone.idle => (PillTone.neutral, LucideIcons.circleDashed),
      StateTone.secret => (PillTone.neutral, LucideIcons.keyRound),
    };
    return StatusPill.tone(
      tone: tone,
      icon: icon,
      label: status.label,
      semanticLabel: 'State: ${status.label}',
    );
  }
}

/// How far along the nearest coin's wait is: a 4px track in the sunken
/// surface, filled in the border colour. Neutrals only; the colour of
/// the state is the pill's to give.
class LockProgress extends StatelessWidget {
  const LockProgress({super.key, required this.progress});

  /// 0 to 1.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final percent = (progress * 100).round();
    return Semantics(
      label: '$percent% of the wait is behind',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GerfautRadius.full),
        child: Container(
          height: 4,
          width: double.infinity,
          color: tokens.surfaceSunken,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: tokens.border),
            ),
          ),
        ),
      ),
    );
  }
}

/// The keys of the policy: label and fingerprint, then origin path and
/// the key itself, shortened. Selectable, so a fingerprint can be
/// checked against a signing device by copying it out.
class _KeysSection extends StatelessWidget {
  const _KeysSection({required this.keys});

  final List<PolicyKey> keys;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final mono = tokens.data.copyWith(fontSize: 12, color: tokens.textMuted);
    final name = tokens.bodySmall.copyWith(
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 500)],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel('Keys', tokens: tokens),
        const SizedBox(height: GerfautSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(GerfautRadius.lg),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, key) in keys.indexed) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: tokens.border.withValues(alpha: 0.5),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GerfautSpacing.md,
                    vertical: GerfautSpacing.sm + GerfautSpacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: key.label, style: name),
                            if (key.fingerprint != null)
                              TextSpan(
                                text: '  ·  ${key.fingerprint}',
                                style: mono,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        key.originPath == null
                            ? key.keyShort
                            : '${key.originPath}  ·  ${key.keyShort}',
                        style: tokens.data.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The descriptor as imported, behind a disclosure closed by default,
/// with the normalized policy under it. Both scroll sideways in their
/// own box: a descriptor is one long line, and wrapping it would break
/// it where nobody breaks it.
class _DescriptorSection extends StatefulWidget {
  const _DescriptorSection({required this.descriptor, required this.policy});

  final String descriptor;
  final String policy;

  @override
  State<_DescriptorSection> createState() => _DescriptorSectionState();
}

class _DescriptorSectionState extends State<_DescriptorSection> {
  bool _open = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.descriptor));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            borderRadius: BorderRadius.circular(GerfautRadius.sm),
            onTap: () => setState(() => _open = !_open),
            child: Container(
              // A 44px tap target around a one-line disclosure.
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                    size: 14,
                    color: tokens.textMuted,
                  ),
                  const SizedBox(width: GerfautSpacing.xs),
                  Flexible(child: FieldLabel('Descriptor', tokens: tokens)),
                ],
              ),
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: GerfautSpacing.xs),
          Stack(
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: tokens.surfaceSunken,
                  borderRadius: BorderRadius.circular(GerfautRadius.md),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(
                    GerfautSpacing.md,
                    GerfautSpacing.md,
                    GerfautSpacing.xxl,
                    GerfautSpacing.md,
                  ),
                  child: Text(widget.descriptor, style: tokens.data),
                ),
              ),
              Positioned(
                top: GerfautSpacing.xs,
                right: GerfautSpacing.xs,
                child: IconButton(
                  onPressed: _copy,
                  tooltip: 'Copy descriptor',
                  iconSize: 16,
                  icon: Icon(
                    _copied ? LucideIcons.check : LucideIcons.copy,
                    color: _copied ? tokens.confirmed : tokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            'Read as',
            style: tokens.label.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: GerfautSpacing.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              widget.policy,
              style: tokens.data.copyWith(
                fontSize: 12,
                color: tokens.textMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
