import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';

/// Receive address display: the full address in mono, copy with
/// explicit feedback, index shown. Single-address wallets show their
/// one address.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key, required this.walletId});

  final String walletId;

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  bool _copied = false;

  Future<void> _copy(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final addresses = ref.watch(receiveProvider(widget.walletId));
    final entry = addresses.valueOrNull?.firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: addresses.hasError
              ? Center(
                  child: Text(
                    'The receive address could not be derived.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                )
              : entry == null
              ? Center(
                  child: Text(
                    'Deriving address…',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'NEXT UNUSED ADDRESS · INDEX ${entry.index}',
                      style: tokens.label.copyWith(color: tokens.textMuted),
                    ),
                    const SizedBox(height: GerfautSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(GerfautSpacing.md),
                      decoration: BoxDecoration(
                        color: tokens.surfaceSunken,
                        borderRadius: BorderRadius.circular(GerfautRadius.sm),
                      ),
                      child: SelectableText(
                        entry.address,
                        style: tokens.data.copyWith(
                          fontSize: tokens.body.fontSize,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: GerfautSpacing.md),
                    Text(
                      'Verify this address on your signing device before '
                      'sharing it. Gerfaut only watches: it never holds the '
                      'keys behind it.',
                      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                    ),
                    const Spacer(),
                    PrimaryButton(
                      label: _copied ? 'Copied' : 'Copy address',
                      icon: _copied ? LucideIcons.check : LucideIcons.copy,
                      expand: true,
                      onPressed: () => _copy(entry.address),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
