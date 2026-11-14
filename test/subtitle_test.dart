import 'package:flutter_test/flutter_test.dart';
import 'package:ai_subtitle_studio/core/utilities/timestamp_utils.dart';
import 'package:ai_subtitle_studio/data/serializers/ass_serializer.dart';
import 'package:ai_subtitle_studio/data/serializers/srt_serializer.dart';
import 'package:ai_subtitle_studio/data/serializers/vtt_serializer.dart';
import 'package:ai_subtitle_studio/domain/entities/subtitle_cue.dart';
import 'package:ai_subtitle_studio/domain/entities/subtitle_style.dart';
import 'package:ai_subtitle_studio/domain/entities/user_settings.dart';
import 'package:ai_subtitle_studio/domain/services/profanity_filter_service.dart';
import 'package:ai_subtitle_studio/domain/services/subtitle_splitting_service.dart';

void main() {
  group('TimestampUtils Tests', () {
    test('SRT formatting and parsing', () {
      const ms = 3661234; // 1 hour, 1 min, 1 sec, 234 ms
      final srt = TimestampUtils.formatSrt(ms);
      expect(srt, '01:01:01,234');
      final parsed = TimestampUtils.parseSrt(srt);
      expect(parsed, ms);
    });

    test('VTT formatting and parsing', () {
      const ms = 125500; // 2 min, 5 sec, 500 ms
      final vtt = TimestampUtils.formatVtt(ms);
      expect(vtt, '00:02:05.500');
      final parsed = TimestampUtils.parseVtt(vtt);
      expect(parsed, ms);
    });

    test('ASS formatting and parsing', () {
      const ms = 3723450; // 1 hr, 2 min, 3.45 sec
      final ass = TimestampUtils.formatAss(ms);
      expect(ass, '1:02:03.45');
      final parsed = TimestampUtils.parseAss(ass);
      expect(parsed, 3723450);
    });
  });

  group('Serializers Tests', () {
    final cues = [
      const SubtitleCue(
        projectId: 'test_p',
        cueIndex: 1,
        startMs: 1000,
        endMs: 4000,
        text: 'Hello world!',
      ),
      const SubtitleCue(
        projectId: 'test_p',
        cueIndex: 2,
        startMs: 4500,
        endMs: 8000,
        text: 'Second line of dialogue.',
      ),
    ];

    test('SRT Round-trip serialization and parsing', () {
      final srt = SrtSerializer.serialize(cues);
      final parsed = SrtSerializer.parse(srt, projectId: 'test_p');
      expect(parsed.length, 2);
      expect(parsed[0].text, 'Hello world!');
      expect(parsed[0].startMs, 1000);
      expect(parsed[0].endMs, 4000);
      expect(parsed[1].text, 'Second line of dialogue.');
    });

    test('VTT Round-trip serialization and parsing', () {
      final vtt = VttSerializer.serialize(cues);
      final parsed = VttSerializer.parse(vtt, projectId: 'test_p');
      expect(parsed.length, 2);
      expect(parsed[0].text, 'Hello world!');
      expect(parsed[1].text, 'Second line of dialogue.');
    });

    test('ASS Round-trip serialization and parsing', () {
      final ass = AssSerializer.serialize(cues, style: const SubtitleStyle());
      final parsed = AssSerializer.parse(ass, projectId: 'test_p');
      expect(parsed.length, 2);
      expect(parsed[0].text, 'Hello world!');
      expect(parsed[1].text, 'Second line of dialogue.');
    });
  });

  group('ProfanityFilterService Tests', () {
    const input = 'This is bullshit and damn annoying.';

    test('Masking policy: None (authentic dialogue preserved)', () {
      final result = ProfanityFilterService.maskText(input, CensorMaskType.none);
      expect(result, input);
    });

    test('Masking policy: Partial', () {
      final result = ProfanityFilterService.maskText(input, CensorMaskType.partial);
      expect(result.contains('b******t'), isTrue);
      expect(result.contains('d**n'), isTrue);
    });

    test('Masking policy: Full', () {
      final result = ProfanityFilterService.maskText(input, CensorMaskType.full);
      expect(result.contains('********'), isTrue);
      expect(result.contains('****'), isTrue);
    });

    test('Masking policy: Placeholder', () {
      final result = ProfanityFilterService.maskText(input, CensorMaskType.placeholder, placeholder: '[censored]');
      expect(result.contains('[censored]'), isTrue);
      expect(result.contains('bullshit'), isFalse);
    });
  });

  group('SubtitleSplittingService Tests', () {
    test('Splits long cues at word boundaries', () {
      const splitter = SubtitleSplittingService(maxCharsPerLine: 25, maxDurationMs: 4000);
      final cue = const SubtitleCue(
        projectId: 'p',
        cueIndex: 1,
        startMs: 0,
        endMs: 10000,
        text: 'This is a very long dialogue that definitely needs to be split across multiple chunks for readability.',
      );

      final split = splitter.splitCues([cue]);
      expect(split.length > 1, isTrue);
      for (final c in split) {
        expect(c.durationMs <= 4000, isTrue);
      }
    });
  });
}
