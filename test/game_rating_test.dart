import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/features/games/game_service.dart';

void main() {
  test('parses star ratings from notes', () {
    expect(parseStarRating('Great game ⭐⭐⭐⭐'), 4);
    expect(parseStarRating('Best one ★★★★★'), 5);
    expect(parseStarRating('4/5 would play'), 4);
    expect(parseStarRating('solid game'), 0);
  });
}
