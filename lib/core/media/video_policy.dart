class VideoPolicy {
  static const int maxBytes = 25 * 1024 * 1024;

  static String? mimeTypeForFilename(String filename) {
    final name = filename.trim().toLowerCase();

    if (name.endsWith('.mp4')) return 'video/mp4';
    if (name.endsWith('.webm')) return 'video/webm';
    if (name.endsWith('.mov')) return 'video/quicktime';

    return null;
  }

  static bool acceptsSize(int bytes) => bytes > 0 && bytes <= maxBytes;
}
