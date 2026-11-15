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
      if (trimmed.isEmpty || trimmed.startsWith('WEBVTT') || trimmed.startsWith('NOTE') || trimmed.startsWith('STYLE')) {
        commitCue();
        continue;
      }

      if (trimmed.contains('-->')) {
        final arrowParts = trimmed.split('-->');
        if (arrowParts.length >= 2) {
          if (currentStart != null && currentTextLines.isNotEmpty) {
            commitCue();
          }
          currentStart = TimestampUtils.parseVtt(arrowParts[0].trim());
          // Ignore VTT cue settings like "line:0 position:20% align:start"
          final endToken = arrowParts[1].trim().split(RegExp(r'\s+')).first;
          currentEnd = TimestampUtils.parseVtt(endToken);
          continue;
        }
      }

      if (currentStart == null && int.tryParse(trimmed) != null) {
        // Skip cue identifier numbers
        continue;
      }

      if (currentStart != null) {
        // Strip basic VTT voice/styling tags like <v Speaker>, <b>, <i>, <c.color>
        final cleanText = trimmed.replaceAll(RegExp(r'<[^>]+>'), '');
        if (cleanText.isNotEmpty) {
          currentTextLines.add(cleanText);
        }
      }
    }
    commitCue();

    return cues;
  }
}
