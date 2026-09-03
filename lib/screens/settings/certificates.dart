import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/format.dart';
import '../../src/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/facts.dart';
import '../../widgets/notice.dart';

/// A fingerprint on its own quiet surface: mono, in rows of eight byte
/// pairs, so it can be read against what the server prints.
class _FingerprintBlock extends StatelessWidget {
  const _FingerprintBlock({
    required this.label,
    required this.fingerprint,
    this.color,
  });

  final String label;
  final String fingerprint;

  /// Ink of the digits; the default is the body colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label, tokens: tokens),
        const SizedBox(height: GerfautSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(GerfautSpacing.sm),
          decoration: BoxDecoration(
            color: tokens.surfaceSunken,
            borderRadius: BorderRadius.circular(GerfautRadius.sm),
          ),
          child: Text(
            groupFingerprint(fingerprint),
            style: tokens.data.copyWith(
              fontSize: 13,
              height: 1.5,
              color: color ?? tokens.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// One thing a certificate says about itself: a quiet label, then the
/// value in the body ink.
class _CertificateFact extends StatelessWidget {
  const _CertificateFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: GerfautSpacing.xs),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          children: [TextSpan(text: value, style: tokens.bodySmall)],
        ),
      ),
    );
  }
}

/// No public authority vouches for this certificate: the user is shown
/// what the server presents and decides once, the way SSH asks.
class UnknownCertificateDialog extends StatelessWidget {
  const UnknownCertificateDialog({
    super.key,
    required this.host,
    required this.status,
  });

  final String host;
  final UnknownCertificate status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final subject = status.subject;
    final expires = status.expires;
    return AlertDialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
      ),
      title: Text('This server signs its own certificate', style: tokens.h2),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No public authority vouches for the certificate of $host. '
                'Compare the fingerprint below with the one your server '
                'shows, then accept it once: Gerfaut remembers it and '
                'refuses anything else afterwards.',
                style: tokens.bodySmall,
              ),
              const SizedBox(height: GerfautSpacing.md),
              _FingerprintBlock(
                label: 'SHA-256 fingerprint',
                fingerprint: status.fingerprint,
              ),
              if (subject != null)
                _CertificateFact(label: 'Subject', value: subject),
              if (expires != null)
                _CertificateFact(
                  label: 'Valid until',
                  value: formatTimestamp(expires),
                ),
              _CertificateFact(label: 'Why it is asked', value: status.reason),
              const SizedBox(height: GerfautSpacing.md),
              Text(
                'On the machine that runs the server, this prints the same '
                'string:',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.xs),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(GerfautSpacing.sm),
                decoration: BoxDecoration(
                  color: tokens.surfaceSunken,
                  borderRadius: BorderRadius.circular(GerfautRadius.sm),
                ),
                child: Text(
                  'openssl x509 -noout -fingerprint -sha256 -in <cert>',
                  style: tokens.data.copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                'Accepting records this fingerprint for $host. Any other '
                'certificate from that host is refused afterwards.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          label: 'Accept and save',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// The accepted certificate is not the one the server presents. Either
/// its operator replaced it, or something sits in between. Refused by
/// default; accepting takes two deliberate steps.
class ChangedCertificateDialog extends StatefulWidget {
  const ChangedCertificateDialog({
    super.key,
    required this.host,
    required this.status,
  });

  final String host;
  final ChangedCertificate status;

  @override
  State<ChangedCertificateDialog> createState() =>
      _ChangedCertificateDialogState();
}

class _ChangedCertificateDialogState extends State<ChangedCertificateDialog> {
  /// Set by the first tap on the trust action; only the second one
  /// accepts anything.
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return AlertDialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
      ),
      title: Text("This server's certificate changed", style: tokens.h2),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Red, and one of the few things that earns it: a
              // fingerprint that changed is either a rotation nobody
              // announced or somebody sitting in the middle, and the
              // second one costs privacy at the very least.
              GerfautNotice(
                tone: NoticeTone.alert,
                message:
                    '${widget.host} was accepted with one certificate '
                    'and now presents another. Either whoever runs it '
                    'replaced it, or something sits between you and it.',
              ),
              const SizedBox(height: GerfautSpacing.md),
              _FingerprintBlock(
                label: 'Accepted before',
                fingerprint: widget.status.stored,
              ),
              const SizedBox(height: GerfautSpacing.sm),
              _FingerprintBlock(
                label: 'Presented now',
                fingerprint: widget.status.presented,
                color: tokens.alert,
              ),
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                'Nothing is saved and nothing is trusted until you say so. '
                'Ask whoever runs the server before accepting the new one.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              if (_confirming) ...[
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  'Trusting it makes Gerfaut accept this certificate for '
                  '${widget.host} from now on. Do it only if you know why '
                  'it changed.',
                  style: tokens.bodySmall.copyWith(
                    color: tokens.alert,
                    fontWeight: FontWeight.w500,
                    fontVariations: const [FontVariation('wght', 500)],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: _confirming
          ? [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              DangerButton(
                label: 'Trust it anyway',
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ]
          : [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: tokens.alert),
                onPressed: () => setState(() => _confirming = true),
                child: const Text('Trust the new certificate'),
              ),
              PrimaryButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
    );
  }
}

/// One accepted certificate: the host it belongs to, its fingerprint,
/// and the way out. Forgetting asks first.
class CertificateRow extends StatelessWidget {
  const CertificateRow({
    super.key,
    required this.host,
    required this.fingerprint,
    required this.tokens,
    required this.confirming,
    required this.onForgetStart,
    required this.onForgetConfirm,
    required this.onCancel,
  });

  final String host;
  final String fingerprint;
  final GerfautTokens tokens;
  final bool confirming;
  final VoidCallback onForgetStart;
  final VoidCallback onForgetConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: GerfautSpacing.sm),
      padding: const EdgeInsets.all(GerfautSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            host,
            style: tokens.data.copyWith(
              fontSize: tokens.bodySmall.fontSize,
              color: tokens.text,
            ),
          ),
          const SizedBox(height: GerfautSpacing.xs),
          Text(
            groupFingerprint(fingerprint),
            style: tokens.data.copyWith(
              fontSize: 12,
              height: 1.5,
              color: tokens.textMuted,
            ),
          ),
          if (confirming) ...[
            const SizedBox(height: GerfautSpacing.sm),
            Text(
              'Gerfaut asks again the next time it connects to $host.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: GerfautSpacing.sm),
            Row(
              children: [
                SecondaryButton(
                  label: 'Forget certificate',
                  onPressed: onForgetConfirm,
                ),
                const SizedBox(width: GerfautSpacing.sm),
                GhostButton(label: 'Cancel', onPressed: onCancel),
              ],
            ),
          ] else ...[
            const SizedBox(height: GerfautSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                label: 'Forget',
                icon: LucideIcons.trash2,
                onPressed: onForgetStart,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
