import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/text/hashtags.dart';

void main() {
  test('hashtags are unique and lowercased in order', () {
    expect(
      Hashtags.extract('MolStr #MolStr is #cool and #molstr again'),
      ['molstr', 'cool'],
    );
  });

  test('no hashtags returns empty', () {
    expect(Hashtags.extract('nothing here'), isEmpty);
  });
}
