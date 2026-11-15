import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_subtitle_studio/domain/entities/subtitle_cue.dart';
import 'package:ai_subtitle_studio/native/media/audio_extractor.dart';
import 'package:ai_subtitle_studio/native/translation/onnx_translation_engine.dart';
import 'package:ai_subtitle_studio/native/translation/unigram_tokenizer.dart';
import 'package:ai_subtitle_studio/native/whisper/whisper_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio & Whisper Native Integration Tests', () {
    test('AudioExtractor rejects corrupt or empty files with explicit error', () async {
      final extractor = AudioExtractor();
      final tempDir = Directory.systemTemp.createTempSync('ai_sub_test');
      final dummyInput = File('${tempDir.path}/test_corrupt.mp4');
      await dummyInput.writeAsBytes(List<int>.filled(100, 0));

      expect(
        () async => await extractor.extractAudio(
          inputPath: dummyInput.path,
          onProgress: (p, s) {},
          outputDir: tempDir.path,
        ),
        throwsA(isA<Exception>()),
      );

      tempDir.deleteSync(recursive: true);
    });

    test('WhisperEngine throws meaningful error when model is not installed', () async {
      final whisper = WhisperEngine();
      final tempDir = Directory.systemTemp.createTempSync('ai_sub_whisper');
      final wavFile = File('${tempDir.path}/test.wav');

      // Create a valid 16kHz mono 16-bit PCM WAV header with 0.5s of silence
      final header = ByteData(44);
      header.setUint32(0, 0x52494646, Endian.big); // "RIFF"
      header.setUint32(4, 36 + 16000, Endian.little);
      header.setUint32(8, 0x57415645, Endian.big); // "WAVE"
      header.setUint32(12, 0x666D7420, Endian.big); // "fmt "
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little); // PCM
      header.setUint16(22, 1, Endian.little); // Mono
      header.setUint32(24, 16000, Endian.little); // 16kHz
      header.setUint32(28, 32000, Endian.little);
      header.setUint16(32, 2, Endian.little);
      header.setUint16(34, 16, Endian.little);
      header.setUint32(36, 0x64617461, Endian.big); // "data"
      header.setUint32(40, 16000, Endian.little);

      final bytes = Uint8List(44 + 16000);
      bytes.setRange(0, 44, header.buffer.asUint8List());
      await wavFile.writeAsBytes(bytes);

      // Call transcribe without model - must throw Exception as required by Phase 2
      expect(
        () async => await whisper.transcribe(
          audioPath: wavFile.path,
          modelPath: '',
          projectId: 'p_test',
          language: 'en',
          onProgress: (p, s) {},
        ),
        throwsA(isA<Exception>()),
      );

      tempDir.deleteSync(recursive: true);
    });
  });

  group('Neural Translation & Tokenizer Tests', () {
    test('UnigramTokenizer encodes and decodes tokens accurately', () async {
      final tempDir = Directory.systemTemp.createTempSync('ai_sub_tok');
      final tokFile = File('${tempDir.path}/tokenizer.json');

      final sampleTokenizerJson = '''
      {
        "version": "1.0",
        "added_tokens": [
          {"id": 0, "content": "<s>"},
          {"id": 1, "content": "</s>"},
          {"id": 2, "content": "<unk>"},
          {"id": 3, "content": "<pad>"}
        ],
        "model": {
          "type": "Unigram",
          "vocab": [
            ["<s>", 0.0],
            ["</s>", 0.0],
            ["<unk>", 0.0],
            ["<pad>", 0.0],
            [" Hello", -1.0],
            [" World", -1.2],
            ["!", -0.5],
            [" Test", -2.0]
          ]
        }
      }
      ''';
      await tokFile.writeAsString(sampleTokenizerJson);

      final tokenizer = await UnigramTokenizer.fromFile(tokFile.path);
      expect(tokenizer.padTokenId, equals(3));
      expect(tokenizer.eosTokenId, equals(1));

      final tokens = tokenizer.encode('Hello World');
      expect(tokens, isNotEmpty);
      expect(tokens.last, equals(tokenizer.eosTokenId));

      final decoded = tokenizer.decode(tokens);
      expect(decoded.toLowerCase(), contains('hello'));

      tempDir.deleteSync(recursive: true);
    });

    test('OnnxTranslationEngine rejects uninstalled language packs with informative error', () async {
      final engine = OnnxTranslationEngine();

      expect(
        () async => await engine.translateText(
          text: 'Hello world',
          sourceLang: 'ja',
          targetLang: 'en',
          packLocalPath: null,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Timestamp preservation during subtitle cue translation', () {
      const originalCue = SubtitleCue(
        id: 1,
        projectId: 'project-xyz',
        cueIndex: 1,
        startMs: 14500,
        endMs: 18200,
        text: 'Original dialogue',
      );

      final translatedCue = originalCue.copyWith(
        text: 'Translated dialogue',
        originalText: originalCue.text,
      );

      // Timestamps must remain strictly unchanged
      expect(translatedCue.startMs, equals(14500));
      expect(translatedCue.endMs, equals(18200));
      expect(translatedCue.cueIndex, equals(1));
      expect(translatedCue.id, equals(1));
      expect(translatedCue.originalText, equals('Original dialogue'));
      expect(translatedCue.text, equals('Translated dialogue'));
    });
  });
}
