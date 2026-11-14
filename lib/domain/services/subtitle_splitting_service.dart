import '../entities/subtitle_cue.dart';

class SubtitleSplittingService {
  final int maxCharsPerLine;
  final int maxDurationMs;
  final int minDurationMs;

  const SubtitleSplittingService({
    this.maxCharsPerLine = 42,
    this.maxDurationMs = 7000,
    this.minDurationMs = 1000,
  });

  /// Splits long cues into smaller, broadcast-compliant subtitle chunks.
  List<SubtitleCue> splitCues(List<SubtitleCue> inputCues) {
    final List<SubtitleCue> result = [];
    int globalIndex = 1;

    for (final cue in inputCues) {
      final text = cue.text.trim();
      final totalDuration = cue.durationMs;

      // If cue is short enough and doesn't exceed duration, keep it
      if (text.length <= maxCharsPerLine * 2 && totalDuration <= maxDurationMs) {
        result.add(cue.copyWith(
          cueIndex: globalIndex++,
          text: _wrapLines(text, maxCharsPerLine),
        ));
        continue;
      }

      // Otherwise, split into multiple chunks
      final chunks = _splitTextIntoChunks(text, maxCharsPerLine * 2);
      if (chunks.length <= 1) {
        result.add(cue.copyWith(
          cueIndex: globalIndex++,
          text: _wrapLines(text, maxCharsPerLine),
        ));
        continue;
      }

      final totalChars = chunks.fold<int>(0, (sum, c) => sum + c.length);
      int currentStart = cue.startMs;

      for (int i = 0; i < chunks.length; i++) {
        final chunkText = chunks[i];
        final fraction = totalChars > 0 ? (chunkText.length / totalChars) : (1.0 / chunks.length);
        final chunkDuration = (totalDuration * fraction).round().clamp(minDurationMs, maxDurationMs);
        final chunkEnd = (i == chunks.length - 1) ? cue.endMs : (currentStart + chunkDuration);

        result.add(SubtitleCue(
          projectId: cue.projectId,
          cueIndex: globalIndex++,
          startMs: currentStart,
          endMs: chunkEnd,
          text: _wrapLines(chunkText, maxCharsPerLine),
          originalText: cue.originalText,
          speaker: cue.speaker,
          customStyle: cue.customStyle,
        ));

        currentStart = chunkEnd;
      }
    }

    return result;
  }

  /// Wraps text to maximum characters per line at word boundaries.
  static String _wrapLines(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final words = text.split(' ');
    final lines = <String>[];
    String currentLine = '';

    for (final word in words) {
      if (currentLine.isEmpty) {
        currentLine = word;
      } else if (currentLine.length + 1 + word.length <= maxChars) {
        currentLine += ' $word';
      } else {
        lines.add(currentLine);
        currentLine = word;
      }
    }
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }
    return lines.join('\n');
  }

  /// Splits text at sentence or punctuation boundaries where possible.
  List<String> _splitTextIntoChunks(String text, int targetChunkLength) {
    // Try punctuation split first
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    if (sentences.length > 1) {
      final List<String> chunks = [];
      String current = '';
      for (final s in sentences) {
        if (current.isEmpty) {
          current = s;
        } else if (current.length + 1 + s.length <= targetChunkLength) {
          current += ' $s';
        } else {
          chunks.add(current);
          current = s;
        }
      }
      if (current.isNotEmpty) chunks.add(current);
      return chunks;
    }

    // Fallback: split by words
    final words = text.split(' ');
    final chunks = <String>[];
    String current = '';

    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= targetChunkLength) {
        current += ' $word';
      } else {
        chunks.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }
}
