import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/disguise.dart';
import '../src/updates.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'notice.dart';

/// The line at the head of the home screen when a newer release is
/// known: what is out, a way to it, and a way to be left alone.
///
/// Information, not pressure. It sits in the page and covers nothing,
/// wears no signal colour, and either button closes it for that release
/// for good. It lives on the home screen only, which the lock replaces
/// rather than covers, and it stays silent while the app is disguised:
/// its one sentence names Gerfaut.
class UpdateNotice extends ConsumerWidget {
  const UpdateNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(updateProvider).notice;
    final disguise = ref.watch(disguiseProvider);
    if (version == null || !disguise.loaded || disguise.disguised) {
      return const SizedBox.shrink();
    }
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final updates = ref.read(updateProvider.notifier);
    final style = tokens.bodySmall.copyWith(
      color: tokens.text,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 500)],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GerfautSpacing.md,
        GerfautSpacing.sm,
        GerfautSpacing.md,
        0,
      ),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            GerfautSpacing.sm + 4,
            GerfautSpacing.sm + 4,
            GerfautSpacing.sm + 4,
            GerfautSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(GerfautRadius.md),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: FirstLine(
                      style: style,
                      child: Icon(
                        LucideIcons.circleArrowUp,
                        size: 16,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: GerfautSpacing.sm),
                  Expanded(
                    child: Text('Gerfaut $version is available', style: style),
                  ),
                ],
              ),
              const SizedBox(height: GerfautSpacing.sm),
              // A Wrap: at a large text size the two buttons take a line
              // each rather than run past the edge.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: GerfautSpacing.sm,
                runSpacing: GerfautSpacing.xs,
                children: [
                  _Hinted(
                    hint: 'Hides this notice until the next release',
                    child: GhostButton(
                      label: 'Later',
                      onPressed: updates.dismiss,
                    ),
                  ),
                  _Hinted(
                    hint: 'Opens the release page in your browser',
                    child: PrimaryButton(
                      label: 'View release',
                      icon: LucideIcons.externalLink,
                      onPressed: () {
                        updates.dismiss();
                        launchUrl(
                          Uri.parse(releasePageUrl),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A button read with what it does after its name: one node for a
/// screen reader, the hint merged into the button's own.
class _Hinted extends StatelessWidget {
  const _Hinted({required this.hint, required this.child});

  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(hint: hint, child: child),
    );
  }
}
