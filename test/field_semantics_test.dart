import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings/fields.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/password_field.dart';

Widget host(Widget child) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('a secret field keeps its name once something is typed', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(PasswordField(label: 'Backup password', controller: controller)),
    );
    await tester.enterText(find.byType(TextField), 'hunter22');
    await tester.pump();

    final field = tester.getSemantics(find.byType(TextField));
    expect(field.label, 'Backup password');
    // The caption is not read a second time on its own, and the eye is
    // still a button with a name of its own.
    expect(find.bySemanticsLabel('BACKUP PASSWORD'), findsNothing);
    expect(find.byTooltip('Show Backup password'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an identifier field is named, not read as its example', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        MonoField(
          label: 'Host',
          controller: controller,
          hint: 'node.example.org',
          onChanged: () {},
          tokens: GerfautTokens.light,
        ),
      ),
    );

    final field = tester.getSemantics(find.byType(TextField));
    expect(field.label, startsWith('Host'));
    handle.dispose();
  });
}
