// Placeholder so `flutter create .` does not generate the default counter-app
// test (which would not compile against SUDOSEND). Real tests: wraith_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:sudosend/core/util.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
  });
}
