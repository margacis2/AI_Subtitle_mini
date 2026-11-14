import '../../core/utilities/timestamp_utils.dart';
import '../../domain/entities/subtitle_cue.dart';

class VttSerializer {
  VttSerializer._();

  /// Serializes a list of SubtitleCues into WebVTT (.vtt) string.
  static String serialize(List<SubtitleCue> cues) {
    final buffer = StringBuffer();
    buffer.writeln('WEBVTT');
    buffer.writeln();

    for (int i = 0; i < cues.length; i++) {
      final cue = cues[i];
      final startStr = TimestampUtils.formatVtt(cue.startMs);
      final endStr = TimestampUtils.formatVtt(cue.endMs);

      buffer.writeln('${i + 1}');
      buffer.writeln('$startStr --> $endStr');
      buffer.writeln(cue.text.trim());
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Parses a WebVTT file string into a list of SubtitleCue objects.
  static List<SubtitleCue> parse(String content, {String projectId = ''}) {
    final List<SubtitleCue> cues = [];
    final lines = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

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
      if (trimmed.isEmpty || trimmed.startsWith('WEBVTT') || trimmed.startsWith('NOTE')) {
        commitCue();
        continue;
      }

      if (trimmed.contains('-->')) {
        final arrowParts = trimmed.split('-->');
        if (arrowParts.length == 2) {
          // VTT arrow may have settings like 'align:start'
          final startPart = arrowParts[0].trim();
          final endPart = arrowParts[1].trim().split(' ').first;
          currentStart = TimestampUtils.parseVtt(startPart);
          currentEnd = TimestampUtils.parseVtt(endPart);
          continue;
        }
      }

      if (currentStart == null && int.tryParse(trimmed) != null) {
        continue;
      }

      if (currentStart != null && currentEnd != null) {
        currentTextLines.add(trimmed);
      }
    }

    commitCue();
    return cues;
  }
}
