import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/core/utils/formatters.dart';

void main() {
  test('formatVote', () {
    expect(Formatters.formatVote(7.8), '7.8');
    expect(Formatters.formatVote(null), '—');
    expect(Formatters.formatVote(0), '—');
  });

  test('formatDate', () {
    expect(Formatters.formatDate('2024-01-15'), '15 Jan 2024');
    expect(Formatters.formatDate(null), '—');
  });

  test('formatRuntime', () {
    expect(Formatters.formatRuntime(92), '1h 32m');
    expect(Formatters.formatRuntime(45), '45m');
  });
}
