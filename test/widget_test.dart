import 'package:flutter_test/flutter_test.dart';
import 'package:sudosend/app/strings.dart';
import 'package:wraith_core/util.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
  });

  test('every English string has an Arabic translation', () {
    expect(missingArabicKeys(), isEmpty);
  });

  test('placeholders are filled', () {
    expect(tr('en', 'to_name', {'name': 'Pi'}), 'To Pi');
    expect(tr('ar', 'to_name', {'name': 'Pi'}), 'إلى Pi');
    expect(tr('ar', 'does_not_exist'), 'does_not_exist');
  });
}
