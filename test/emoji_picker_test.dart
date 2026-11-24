import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/ui/widgets/emoji_picker.dart';

void main() {
  testWidgets('emoji sheet returns the tapped emoji', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                picked = await showEmojiPickerSheet(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😀').first);
    await tester.pumpAndSettle();

    expect(picked, '😀');
  });
}
