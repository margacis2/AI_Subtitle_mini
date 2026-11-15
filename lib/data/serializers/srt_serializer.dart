import '../../core/utilities/timestamp_utils.dart';
import '../../domain/entities/subtitle_cue.dart';

class SrtSerializer {
  SrtSerializer._();

  /// Serializes a list of SubtitleCues into standard SubRip (.srt) string.
  static String serialize(List<SubtitleCue> cues) {
    final buffer = StringBuffer();
    for (int i = 0; i < cues.length; i++) {
      final cue = cues[i];
      final startStr = TimestampUtils.formatSrt(cue.startMs);
      final endStr = TimestampUtils.formatSrt(cue.endMs);

      buffer.writeln('${i + 1}');
      buffer.writeln('$startStr --> $endStr');
      buffer.writeln(cue.text.trim());
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Parses an SRT file string into a list of SubtitleCue objects.
  static List<SubtitleCue> parse(String content, {String projectId = ''}) {
    final List<SubtitleCue> cues = [];
    final cleanContent = content.replaceFirst('\uFEFF', '');
    final lines = cleanContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

    int index = 0;
    int? currentStart;
    int? currentEnd;
    final List<String> currentTextLines = [];

    void commitCue() {
      if (currentStart != null && currentEnd != null && currentTextLines.isNotEmpty) {
        index++;
        final text = currentTextLines.join('\n').trim();
        if (text.isNotEmpty) {
          cues.add(SubtitleCue(
            projectId: projectId,
            cueIndex: index,
            startMs: currentStart!,
            endMs: currentEnd!,
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

      if (trimmed.contains('-->')) {
        final arrowParts = trimmed.split('-->');
        if (arrowParts.length >= 2) {
          // If a previous cue had timestamps pending without an empty line separator, commit it
          if (currentStart != null && currentTextLines.isNotEmpty) {
            commitCue();
          }
          currentStart = TimestampUtils.parseSrt(arrowParts[0].trim());
          // Handle coordinates / formatting attached to end timestamp (e.g., "00:00:05,000 X1:000")
          final endToken = arrowParts[1].trim().split(' ').first;
          currentEnd = TimestampUtils.parseSrt(endToken);
          continue;
        }
      }

      // Ignore sequence number if not yet tracking a cue
      if (currentStart == null && int.tryParse(trimmed) != null) {
        continue;
      }

      if (currentStart != null) {
        currentTextLines.add(trimmed);
      }
    }
    commitCue();

    return cues;
  }
}
