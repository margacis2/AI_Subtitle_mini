/// Utility class for formatting and parsing subtitle timestamps (SRT, VTT, ASS).
class TimestampUtils {
  TimestampUtils._();

  /// Formats milliseconds to SRT timestamp: `HH:mm:ss,SSS`
  static String formatSrt(int ms) {
    if (ms < 0) ms = 0;
    final int hours = ms ~/ 3600000;
    final int minutes = (ms % 3600000) ~/ 60000;
    final int seconds = (ms % 60000) ~/ 1000;
    final int millis = ms % 1000;

    final hStr = hours.toString().padLeft(2, '0');
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    final msStr = millis.toString().padLeft(3, '0');

    return '$hStr:$mStr:$sStr,$msStr';
  }

  /// Formats milliseconds to WebVTT timestamp: `HH:mm:ss.SSS`
  static String formatVtt(int ms) {
    if (ms < 0) ms = 0;
    final int hours = ms ~/ 3600000;
    final int minutes = (ms % 3600000) ~/ 60000;
    final int seconds = (ms % 60000) ~/ 1000;
    final int millis = ms % 1000;

    final hStr = hours.toString().padLeft(2, '0');
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    final msStr = millis.toString().padLeft(3, '0');

    return '$hStr:$mStr:$sStr.$msStr';
  }

  /// Formats milliseconds to ASS timestamp: `H:mm:ss.cc` (centiseconds)
  static String formatAss(int ms) {
    if (ms < 0) ms = 0;
    final int hours = ms ~/ 3600000;
    final int minutes = (ms % 3600000) ~/ 60000;
    final int seconds = (ms % 60000) ~/ 1000;
    final int centis = (ms % 1000) ~/ 10;

    final hStr = hours.toString();
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    final csStr = centis.toString().padLeft(2, '0');

    return '$hStr:$mStr:$sStr.$csStr';
  }

  /// Formats milliseconds into human-readable duration: `mm:ss` or `hh:mm:ss`
  static String formatDuration(int ms) {
    if (ms < 0) ms = 0;
    final int hours = ms ~/ 3600000;
    final int minutes = (ms % 3600000) ~/ 60000;
    final int seconds = (ms % 60000) ~/ 1000;

    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final hStr = hours.toString().padLeft(2, '0');
      return '$hStr:$mStr:$sStr';
    }
    return '$mStr:$sStr';
  }

  /// Parses an SRT timestamp (`00:00:00,000`) to milliseconds.
  static int parseSrt(String s) {
    final clean = s.trim().replaceAll(',', '.');
    return parseVtt(clean);
  }

  /// Parses a WebVTT timestamp (`00:00:00.000` or `00:00.000`) to milliseconds.
  static int parseVtt(String s) {
    final clean = s.trim().replaceAll(',', '.');
    final parts = clean.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final secParts = parts[2].split('.');
      final sec = int.tryParse(secParts[0]) ?? 0;
      final ms = secParts.length > 1
          ? int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0
          : 0;
      return (h * 3600000) + (m * 60000) + (sec * 1000) + ms;
    } else if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final secParts = parts[1].split('.');
      final sec = int.tryParse(secParts[0]) ?? 0;
      final ms = secParts.length > 1
          ? int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0
          : 0;
      return (m * 60000) + (sec * 1000) + ms;
    }
    return 0;
  }

  /// Parses an ASS timestamp (`0:00:00.00`) to milliseconds.
  static int parseAss(String s) {
    final clean = s.trim();
    final parts = clean.split(':');
    if (parts.length >= 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final secParts = parts[2].split('.');
      final sec = int.tryParse(secParts[0]) ?? 0;
      final centis = secParts.length > 1
          ? int.tryParse(secParts[1].padRight(2, '0').substring(0, 2)) ?? 0
          : 0;
      return (h * 3600000) + (m * 60000) + (sec * 1000) + (centis * 10);
    }
    return 0;
  }
}
