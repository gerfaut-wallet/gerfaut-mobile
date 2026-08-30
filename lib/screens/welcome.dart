import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/onboarding.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/buttons.dart';

/// One page of the tour.
typedef WelcomePage = ({IconData icon, String title, String body});

/// What Gerfaut says about itself, once, on a vault that holds nothing
/// yet. Four facts, in the order they matter.
const List<WelcomePage> welcomePages = [
  (
    icon: LucideIcons.eye,
    title: 'Watch, never spend',
    body:
        'Gerfaut holds no key and signs nothing. It watches the wallets '
        'you give it: a descriptor, an extended public key, an address.',
  ),
  (
    icon: LucideIcons.plus,
    title: 'Add a wallet',
    body:
        'Paste it, scan a QR code or open a file. Gerfaut says what it '
        'recognized before it stores anything.',
  ),
  (
    icon: LucideIcons.server,
    title: 'Choose who you talk to',
    body:
        'Public servers by default, or your own node: Esplora or '
        'Electrum, over Tor if you like.',
  ),
  (
    icon: LucideIcons.lock,
    title: 'Keep it yours',
    body:
        'Lock the app, back up your list of wallets, and get told when a '
        'transaction lands.',
  ),
];

/// The welcome tour: shown on a first launch, replayable from the
/// settings, and dismissible at any point.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _done() => ref.read(onboardingSeenProvider.notifier).markSeen();

  void _goTo(BuildContext context, int target) {
    // A device asking for less motion gets the page, not the slide.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _next(BuildContext context) {
    if (_index == welcomePages.length - 1) {
      _done();
      return;
    }
    _goTo(context, _index + 1);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final last = _index == welcomePages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(GerfautSpacing.sm),
              child: Row(
                children: [
                  // A page one can only leave or pass is re-read by
                  // starting the tour over. The swipe already goes back;
                  // the button is what makes it visible. It takes the
                  // left of the row Skip has to itself on the first page.
                  if (_index > 0)
                    GhostButton(
                      label: 'Back',
                      onPressed: () => _goTo(context, _index - 1),
                    ),
                  const Spacer(),
                  GhostButton(label: 'Skip', onPressed: _done),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: welcomePages.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) =>
                    _Page(page: welcomePages[index], first: index == 0),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < welcomePages.length; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index ? tokens.primary : tokens.border,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(GerfautSpacing.md),
              child: PrimaryButton(
                label: last ? 'Get started' : 'Next',
                expand: true,
                onPressed: () => _next(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.page, required this.first});

  final WelcomePage page;

  /// The first page is where the app introduces itself by name; the
  /// others carry their icon alone.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    // Centred in the page, not stacked at its top: a scroll view sizes
    // itself to its content, so it needs the viewport's height back
    // before `center` means anything.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: GerfautSpacing.xl),
              if (first)
                GerfautLockup(
                  color: tokens.primary,
                  width: 160,
                  semanticLabel: 'Gerfaut',
                )
              else
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: tokens.surfaceSunken,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(page.icon, size: 32, color: tokens.primary),
                ),
              const SizedBox(height: GerfautSpacing.lg),
              Text(page.title, style: tokens.h1, textAlign: TextAlign.center),
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                page.body,
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: GerfautSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
