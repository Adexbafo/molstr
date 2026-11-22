import 'package:molstr/features/onboarding/import_key_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/features/onboarding/onboarding_page.dart';

void main() {
  testWidgets('onboarding shows the identity choices', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingPage()),
    );

    expect(find.text('Your identity belongs to you'), findsOneWidget);
    expect(find.text('Create a new key'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Import an existing key'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Import an existing key'), findsOneWidget);
  });

  testWidgets('import page renders the key field', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ImportKeyPage()),
    );

    expect(find.text('Import your Nostr identity'), findsOneWidget);
    expect(find.text('nsec key'), findsOneWidget);
  });
}
