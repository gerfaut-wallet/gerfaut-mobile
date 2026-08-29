import 'package:flutter/material.dart';

/// A form whose one primary action sits at the bottom of the screen.
///
/// With room to spare the action stays pinned at the bottom, within
/// thumb reach. When the keyboard takes that room, the whole form
/// scrolls instead: the action is reached by scrolling, never cut off
/// under the keyboard, which is what happened on a 16:9 phone.
class PinnedActionForm extends StatelessWidget {
  const PinnedActionForm({
    super.key,
    required this.children,
    required this.action,
  });

  /// The form, top to bottom, stretched to the full width.
  final List<Widget> children;

  /// The primary action, kept at the bottom.
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            // The intrinsic height lets the spacer take what the
            // viewport leaves; once the content outgrows it, the column
            // simply grows and scrolls.
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...children, const Spacer(), action],
              ),
            ),
          ),
        );
      },
    );
  }
}
