import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/ui/render/note_text.dart';

void main() {
  testWidgets('renders a video URL as an external video tile', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NoteText(
            content: 'Watch https://example.com/video.mp4',
            selectable: false,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    expect(find.text('Open video from example.com'), findsOneWidget);
  });

  testWidgets('does not treat a video URL as an image', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NoteText(
            content: 'https://example.com/video.webm',
            loadImages: true,
            selectable: false,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
  });
}
