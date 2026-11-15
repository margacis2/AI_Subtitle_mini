import '../../domain/entities/subtitle_cue.dart';

enum TxtImportMode {
  timestamped,
  plainDialogue,
}

class TxtSerializer {
  TxtSerializer._();

  static final RegExp _timestampPattern = RegExp(
    r'(?:\[?(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d{1,3})?)\]?\s*(?:-->|-|to)\s*\[?(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d{1,3})?)\]?)',
    caseSensitive: false,
  );

  static final RegExp _singleTimestampPattern = RegExp(
    r'^[\[\(]?(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d{1,3})?)[\]\)]?\s*(.*)$',
  );

  /// Automatically checks if the text file contains recognizable timestamp patterns.
  static bool hasTimestamps(String content) {
    final clean = content.replaceFirst('\uFEFF', '');
    final lines = clean.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    int matches = 0;
    for (final line in lines.take(30)) {
      final t = line.trim();
      if (_timestampPattern.hasMatch(t) || _singleTimestampPattern.hasMatch(t)) {
        matches++;
      }
    }
    return matches >= 2;
  }

  /// Parses TXT file according to detected or specified mode.
  static List<SubtitleCue> parse(
    String content, {
    String projectId = '',
    TxtImportMode? mode,
  }) {
    final clean = content.replaceFirst('\uFEFF', '');
    final effectiveMode = mode ?? (hasTimestamps(clean) ? TxtImportMode.timestamped : TxtImportMode.plainDialogue);

    if (effectiveMode == TxtImportMode.timestamped) {
      return _parseTimestamped(clean, projectId);
    } else {
      return _parsePlainDialogue(clean, projectId);
    }
  }

  /// Mode A: Parses recognizable timestamp patterns in text files
  static List<SubtitleCue> _parseTimestamped(String content, String projectId) {
    final List<SubtitleCue> cues = [];
    final lines = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

    int index = 0;
    int? currentStart;
    int? currentEnd;
    final List<String> currentTextLines = [];

    void commitCue() {
      if (currentStart != null && currentTextLines.isNotEmpty) {
        index++;
        final text = currentTextLines.join('\n').trim();
        if (text.isNotEmpty) {
          final endMs = currentEnd ?? (currentStart! + 3000);
          cues.add(SubtitleCue(
            projectId: projectId,
            cueIndex: index,
            startMs: currentStart!,
            endMs: endMs,
            text: text,
          ));
        }
      }
      currentStart = null;
      currentEnd = null;
      currentTextLines.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        commitCue();
        continue;
      }

      // Check range pattern: "00:01:20.000 --> 00:01:25.000 text" or "01:20 - 01:25 text"
      final rangeMatch = _timestampPattern.firstMatch(trimmed);
      if (rangeMatch != null) {
        commitCue();
        currentStart = _parseFlexibleTimestamp(rangeMatch.group(1)!);
        currentEnd = _parseFlexibleTimestamp(rangeMatch.group(2)!);
        final remaining = trimmed.substring(rangeMatch.end).trim();
        if (remaining.isNotEmpty) {
          currentTextLines.add(remaining.replaceFirst(RegExp(r'^[:\-]\s*'), ''));
        }
        continue;
      }

      // Check single timestamp pattern: "[01:23.45] text"
      final singleMatch = _singleTimestampPattern.firstMatch(trimmed);
      if (singleMatch != null) {
        commitCue();
        currentStart = _parseFlexibleTimestamp(singleMatch.group(1)!);
        final remaining = singleMatch.group(2)!.trim();
        if (remaining.isNotEmpty) {
          currentTextLines.add(remaining);
        }
        continue;
      }

      if (currentStart != null) {
        currentTextLines.add(trimmed);
      }
    }
    commitCue();

    // If timestamped parsing produced empty cues, fall back to plain dialogue
    if (cues.isEmpty) {
      return _parsePlainDialogue(content, projectId);
    }

    return cues;
  }

  /// Mode B: Parses ordinary text as dialogue with estimated pacing.
  static List<SubtitleCue> _parsePlainDialogue(String content, String projectId) {
    final List<SubtitleCue> cues = [];
    final lines = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

    int index = 0;
    int currentMs = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Estimate pacing: ~15 characters per second, minimum 2000ms, maximum 6000ms
      final duration = ((trimmed.length / 15.0) * 1000).round().clamp(2000, 6000);
      index++;

      cues.add(SubtitleCue(
        projectId: projectId,
        cueIndex: index,
        startMs: currentMs,
        endMs: currentMs + duration,
        text: trimmed,
      ));

      currentMs += duration + 100; // 100ms interval between utterances
    }

    return cues;
  }

  static int _parseFlexibleTimestamp(String s) {
    final clean = s.trim().replaceAll(',', '.');
    final parts = clean.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final secParts = parts[2].split('.');
      final sec = int.tryParse(secParts[0]) ?? 0;
      final ms = secParts.length > 1 ? (int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0) : 0;
      return (h * 3600 + m * 60 + sec) * 1000 + ms;
    } else if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final secParts = parts[1].split('.');
      final sec = int.tryParse(secParts[0]) ?? 0;
      final ms = secParts.length > 1 ? (int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0) : 0;
      return (m * 60 + sec) * 1000 + ms;
    }
    return 0;
  }
}
