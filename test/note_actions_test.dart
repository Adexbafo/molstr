import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/nostr/note_engagement.dart';
import 'package:molstr/ui/render/note_actions.dart';

void main() {
  final sampleNote = NostrEvent.sign(
    privateKeyHex: List.filled(32, '77').join(),
    kind: 1,
    content: 'Testing counts',
    createdAt: 1700000000,
  );

  testWidgets('does not show fake zeros when counts are unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteActionBar(
            event: sampleNote,
            profile: null,
            loadImages: false,
            engagement: null,
          ),
        ),
      ),
    );

    expect(find.text('0'), findsNothing);
  });

  testWidgets('displays observed reply, repost, and like counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteActionBar(
            event: sampleNote,
            profile: null,
            loadImages: false,
            engagement: const NoteEngagement(
              replies: 3,
              likes: 5,
              reposts: 2,
            ),
          ),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });
}
