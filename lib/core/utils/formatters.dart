/// Small formatting helpers (kept dependency-free — no `intl` needed).
class Formatters {
  Formatters._();

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Converts a TMDB `yyyy-MM-dd` date into `dd MMM yyyy`.
  static String formatDate(String? isoDate) {
    if (isoDate == null || isoDate.length < 10) return '—';
    final year = int.tryParse(isoDate.substring(0, 4));
    final month = int.tryParse(isoDate.substring(5, 7));
    final day = int.tryParse(isoDate.substring(8, 10));
    if (year == null ||
        month == null ||
        day == null ||
        month < 1 ||
        month > 12) {
      return isoDate;
    }
    return '$day ${_months[month - 1]} $year';
  }

  /// Converts minutes into `1h 32m`.
  static String formatRuntime(int? minutes) {
    if (minutes == null || minutes <= 0) return '—';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  /// `7.8` → `7.8`.
  static String formatVote(double? vote) {
    if (vote == null || vote <= 0) return '—';
    return vote.toStringAsFixed(1);
  }

  /// `2:05:33` or `05:33` style media timestamp.
  static String formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}
