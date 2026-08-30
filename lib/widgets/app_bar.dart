import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The one header of the app.
///
/// A page with a back arrow puts its title against the arrow: what the
/// title gives up on the left, the actions take on the right, and every
/// action of the page fits in the bar instead of hiding under a menu. A
/// root page, which has no arrow, opens at the page margin like its own
/// content does.
///
/// Material's default adds 16px after the leading whatever the page is,
/// which is what made the wallet screen — the only one that corrected
/// it by hand — sit differently from Settings, Add a wallet and
/// Broadcast. The rule lives here now so no screen can drift again.
class GerfautAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GerfautAppBar({super.key, required this.title, this.actions});

  /// Usually a [Text]; the wallet screen makes it a tap target that
  /// opens the rename dialog.
  final Widget title;
  final List<Widget>? actions;

  /// A plain titled header, the common case.
  factory GerfautAppBar.text(String title, {List<Widget>? actions}) {
    return GerfautAppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    // `ModalRoute.canPop` is what AppBar itself asks before drawing a
    // back arrow, so the two never disagree.
    final hasBack = ModalRoute.of(context)?.canPop ?? false;
    return AppBar(
      titleSpacing: hasBack ? 0 : GerfautSpacing.md,
      title: title,
      actions: actions,
    );
  }
}
