import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';

void main() {
  testWidgets('empty state shows the guidance and its single action', (
    tester,
  ) async {
    await tester.pumpWidget(const GerfautApp());
    await tester.pumpAndSettle();

    expect(find.text('No wallets yet'), findsOneWidget);
    expect(find.text('Add a wallet'), findsOneWidget);
  });

  testWidgets('a faked bootstrap resolves into the home screen', (
    tester,
  ) async {
    await tester.pumpWidget(GerfautApp(bootstrap: () async {}));
    await tester.pumpAndSettle();

    expect(find.text('No wallets yet'), findsOneWidget);
    expect(find.text('Add a wallet'), findsOneWidget);
  });

  testWidgets('a failed bootstrap shows the startup error screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      GerfautApp(bootstrap: () async => throw StateError('vault init failed')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gerfaut could not start'), findsOneWidget);
    expect(find.text('No wallets yet'), findsNothing);
  });

  testWidgets('add a wallet opens the placeholder dialog', (tester) async {
    await tester.pumpWidget(const GerfautApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a wallet'));
    await tester.pumpAndSettle();
    expect(
      find.text('Importing wallets is not available yet.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Importing wallets is not available yet.'), findsNothing);
  });
}
