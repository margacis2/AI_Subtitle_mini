import 'package:flutter_test/flutter_test.dart';
import 'package:ai_subtitle_studio/core/utilities/timestamp_utils.dart';
import 'package:ai_subtitle_studio/data/serializers/ass_serializer.dart';
import 'package:ai_subtitle_studio/data/serializers/srt_serializer.dart';
import 'package:ai_subtitle_studio/data/serializers/txt_serializer.dart';
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

    test('ASS dialogue strips override tags properly', () {
      const assRaw = '''[Script Info]
Title: Test
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:01:00.00,0:01:05.00,Default,,0,0,0,,{\\pos(100,200)\\c&H00FFFF&}Important text{\\r} here
''';
      final parsed = AssSerializer.parse(assRaw, projectId: 'p_ass');
      expect(parsed.length, 1);
      expect(parsed[0].text, 'Important text here');
      expect(parsed[0].startMs, 60000);
      expect(parsed[0].endMs, 65000);
    });
  });

  group('TxtSerializer Tests', () {
    test('Mode A: Parses timestamped TXT with bracket timestamps', () {
      const txt = '''
[00:01:10.000 --> 00:01:15.000] Welcome to our presentation.
[00:01:16.500 --> 00:01:20.000] Today we discuss offline AI.
''';
      final cues = TxtSerializer.parse(txt, projectId: 'p_txt_a');
      expect(cues.length, 2);
      expect(cues[0].text, 'Welcome to our presentation.');
      expect(cues[0].startMs, 70000);
      expect(cues[0].endMs, 75000);
      expect(cues[1].text, 'Today we discuss offline AI.');
      expect(cues[1].startMs, 76500);
      expect(cues[1].endMs, 80000);
    });

    test('Mode B: Plain dialogue TXT generates segmented cues with estimated pacing', () {
      const plainTxt = '''
First paragraph of speech dialogue.
Second paragraph of conversation.
Third line of plain narration.
''';
      final cues = TxtSerializer.parse(plainTxt, projectId: 'p_txt_b');
      expect(cues.length, 3);
      expect(cues[0].text, 'First paragraph of speech dialogue.');
      expect(cues[0].startMs, 0);
      expect(cues[0].endMs, greaterThan(0));
      expect(cues[1].startMs, equals(cues[0].endMs + 100));
      expect(cues[2].startMs, equals(cues[1].endMs + 100));
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
