// Driving the overflow menu of a page header, the way a finger does:
// the three dots, then the entry by its label.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the header's overflow menu.
Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
}

/// Opens the menu and picks the entry labelled [label].
Future<void> pickFromMenu(WidgetTester tester, String label) async {
  await openMenu(tester);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// The height of the menu row carrying [label]: whatever a menu holds,
/// a finger has to be able to hit it.
double menuRowHeight(WidgetTester tester, String label) {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(InkWell))
      .first;
  return tester.getSize(row).height;
}
