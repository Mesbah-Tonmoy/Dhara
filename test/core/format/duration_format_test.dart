import 'package:dhara/core/format/duration_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats times under an hour as m:ss', () {
    expect(formatDuration(Duration.zero), '0:00');
    expect(formatDuration(const Duration(seconds: 5)), '0:05');
    expect(formatDuration(const Duration(seconds: 65)), '1:05');
    expect(formatDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
  });

  test('formats times from an hour up as h:mm:ss', () {
    expect(formatDuration(const Duration(hours: 1)), '1:00:00');
    expect(
      formatDuration(const Duration(hours: 2, minutes: 3, seconds: 4)),
      '2:03:04',
    );
    expect(formatDuration(const Duration(hours: 12, minutes: 30)), '12:30:00');
  });

  test('drops fractions of a second and never goes negative', () {
    expect(formatDuration(const Duration(milliseconds: 1999)), '0:01');
    expect(formatDuration(const Duration(seconds: -3)), '0:00');
  });
}
