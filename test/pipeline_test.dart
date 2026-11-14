import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_subtitle_studio/core/utilities/timestamp_utils.dart';
import 'package:ai_subtitle_studio/domain/entities/subtitle_cue.dart';
import 'package:ai_subtitle_studio/native/media/audio_extractor.dart';
import 'package:ai_subtitle_studio/native/translation/onnx_translation_engine.dart';
import 'package:ai_subtitle_studio/native/whisper/whisper_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio & Whisper Transcription Pipeline Tests', () {
    test('AudioExtractor generates valid 16kHz WAV file', () async {
      final extractor = AudioExtractor();
      final tempDir = Directory.systemTemp.createTempSync('ai_sub_test');
      final dummyInput = File('${tempDir.path}/test_media.mp4');
      await dummyInput.writeAsBytes(List<int>.filled(1024, 0));

      final extractedWav = await extractor.extractAudio(
        inputPath: dummyInput.path,
        knownDurationMs: 10000,
        onProgress: (_, __) {},
        outputDir: tempDir.path,
      );

      expect(await extractedWav.exists(), isTrue);
      expect(await extractedWav.length(), greaterThan(44));

      // Test Whisper transcription on the extracted audio
      final whisper = WhisperEngine();
      final cues = await whisper.transcribe(
        audioPath: extractedWav.path,
        modelPath: '',
        projectId: 'test_project_1',
        language: 'en',
        onProgress: (_, __) {},
      );

      expect(cues.isNotEmpty, isTrue);
      expect(cues.first.projectId, equals('test_project_1'));
      expect(cues.first.startMs, greaterThanOrEqualTo(0));
      expect(cues.first.endMs, greaterThan(cues.first.startMs));
      expect(cues.first.text.isNotEmpty, isTrue);

      tempDir.deleteSync(recursive: true);
    });

    test('Translation Engine preserves exact cue timestamps', () async {
      final engine = OnnxTranslationEngine();

      final originalCues = [
        const SubtitleCue(
          projectId: 'p1',
          cueIndex: 1,
          startMs: 1000,
          endMs: 3500,
          text: 'Welcome to AI Sub Mini.',
        ),
        const SubtitleCue(
          projectId: 'p1',
          cueIndex: 2,
          startMs: 4000,
          endMs: 7500,
          text: 'All speech-to-text processing runs securely on your local device.',
        ),
      ];

      // Translate to Spanish
      final translatedCues = <SubtitleCue>[];
      for (final cue in originalCues) {
        final translatedText = await engine.translateText(
          text: cue.text,
          sourceLang: 'en',
          targetLang: 'es',
        );
        translatedCues.add(cue.copyWith(
          text: translatedText,
          originalText: cue.text,
        ));
      }

      expect(translatedCues.length, equals(2));
      // Verify exact timestamps preserved
      expect(translatedCues[0].startMs, equals(1000));
      expect(translatedCues[0].endMs, equals(3500));
      expect(translatedCues[0].text, equals('Bienvenido a AI Sub Mini.'));
      expect(translatedCues[0].originalText, equals('Welcome to AI Sub Mini.'));

      expect(translatedCues[1].startMs, equals(4000));
      expect(translatedCues[1].endMs, equals(7500));
      expect(translatedCues[1].text, contains('Todo el procesamiento'));
    });
  });
}
