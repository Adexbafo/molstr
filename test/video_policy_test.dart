import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/media/video_policy.dart';

void main() {
  test('recognizes supported video extensions', () {
    expect(VideoPolicy.mimeTypeForFilename('clip.mp4'), 'video/mp4');
    expect(VideoPolicy.mimeTypeForFilename('clip.WEBM'), 'video/webm');
    expect(VideoPolicy.mimeTypeForFilename('clip.mov'), 'video/quicktime');
  });

  test('rejects unsupported extensions', () {
    expect(VideoPolicy.mimeTypeForFilename('photo.jpg'), isNull);
    expect(VideoPolicy.mimeTypeForFilename('clip.mp4.exe'), isNull);
  });

  test('enforces the video size limit', () {
    expect(VideoPolicy.acceptsSize(0), isFalse);
    expect(VideoPolicy.acceptsSize(1), isTrue);
    expect(VideoPolicy.acceptsSize(VideoPolicy.maxBytes), isTrue);
    expect(VideoPolicy.acceptsSize(VideoPolicy.maxBytes + 1), isFalse);
  });
}
