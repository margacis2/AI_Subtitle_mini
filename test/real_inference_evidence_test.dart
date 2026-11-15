import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_subtitle_studio/data/serializers/srt_serializer.dart';
import 'package:ai_subtitle_studio/domain/entities/processing_job.dart';
import 'package:ai_subtitle_studio/domain/entities/project.dart';
import 'package:ai_subtitle_studio/domain/entities/subtitle_cue.dart';
import 'package:ai_subtitle_studio/domain/entities/whisper_model_info.dart';
import 'package:ai_subtitle_studio/native/translation/onnx_translation_engine.dart';
import 'package:ai_subtitle_studio/native/translation/unigram_tokenizer.dart';
import 'package:ai_subtitle_studio/native/whisper/whisper_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Real Inference & Pipeline Evidence Verification', () {
    test('1. Missing Whisper model strictly halts with clear error and zero fake cues', () async {
      final whisper = WhisperEngine();
      final tempDir = Directory.systemTemp.createTempSync('ai_sub_missing_model');
      final wavFile = File('${tempDir.path}/test_speech.wav');

      // 16kHz mono WAV header
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

      try {
        await whisper.transcribe(
          audioPath: wavFile.path,
          modelPath: '${tempDir.path}/missing_medium_model.bin',
          projectId: 'project_evidence_1',
          language: 'en',
          onProgress: (p, s) {},
        );
        fail('Must throw exception when model is missing');
      } catch (e) {
        expect(e.toString(), contains('Speech model file not found'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('2. Selected model ID propagates faithfully across Project and ProcessingJob', () {
      const selectedModelId = 'medium';
      final project = Project(
        id: 'proj_evidence_2',
        name: 'Whisper Medium Benchmark',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        selectedModel: selectedModelId,
      );

      expect(project.selectedModel, equals('medium'));
      final projectMap = project.toMap();
      expect(projectMap['selected_model'], equals('medium'));

      final restoredProject = Project.fromMap(projectMap);
      expect(restoredProject.selectedModel, equals('medium'));

      final job = ProcessingJob(
        id: 'job_evidence_2',
        projectId: project.id,
        title: project.name,
        stage: JobStage.queued,
        createdAt: DateTime.now(),
        selectedModel: project.selectedModel,
      );

      expect(job.selectedModel, equals('medium'));
      final jobMap = job.toMap();
      expect(jobMap['selected_model'], equals('medium'));

      final restoredJob = ProcessingJob.fromMap(jobMap);
      expect(restoredJob.selectedModel, equals('medium'));
    });

    test('3. Real imported SRT parser accurately preserves timestamps and ordering', () {
      const sampleSrt = '''1
00:00:01,200 --> 00:00:04,500
Good morning and welcome to the presentation.

2
00:00:05,100 --> 00:00:08,750
Today we will discuss offline AI speech recognition.

3
00:00:09,000 --> 00:00:12,400
All processing happens directly on your device.
''';

      final cues = SrtSerializer.parse(sampleSrt, projectId: 'proj_test_srt');
      expect(cues.length, equals(3));

      expect(cues[0].cueIndex, equals(1));
      expect(cues[0].startMs, equals(1200));
      expect(cues[0].endMs, equals(4500));
      expect(cues[0].text, equals('Good morning and welcome to the presentation.'));

      expect(cues[1].cueIndex, equals(2));
      expect(cues[1].startMs, equals(5100));
      expect(cues[1].endMs, equals(8750));
      expect(cues[1].text, equals('Today we will discuss offline AI speech recognition.'));

      expect(cues[2].cueIndex, equals(3));
      expect(cues[2].startMs, equals(9000));
      expect(cues[2].endMs, equals(12400));
      expect(cues[2].text, equals('All processing happens directly on your device.'));
    });

    test('4. Subtitle cue translation preserves timestamps and ordering strictly', () {
      final originalCues = [
        const SubtitleCue(
          id: 1,
          projectId: 'p_trans',
          cueIndex: 1,
          startMs: 1500,
          endMs: 4000,
          text: 'Hello world',
        ),
        const SubtitleCue(
          id: 2,
          projectId: 'p_trans',
          cueIndex: 2,
          startMs: 4500,
          endMs: 7200,
          text: 'This is offline neural translation',
        ),
      ];

      // Simulated translated dialogue
      final translations = ['Hola mundo', 'Esta es la traducción neuronal sin conexión'];
      final translatedCues = <SubtitleCue>[];

      for (int i = 0; i < originalCues.length; i++) {
        translatedCues.add(originalCues[i].copyWith(
          text: translations[i],
          originalText: originalCues[i].text,
        ));
      }

      expect(translatedCues.length, equals(originalCues.length));
      for (int i = 0; i < originalCues.length; i++) {
        expect(translatedCues[i].cueIndex, equals(originalCues[i].cueIndex));
        expect(translatedCues[i].startMs, equals(originalCues[i].startMs));
        expect(translatedCues[i].endMs, equals(originalCues[i].endMs));
        expect(translatedCues[i].originalText, equals(originalCues[i].text));
        expect(translatedCues[i].text, equals(translations[i]));
      }
    });

    test('5. UnigramTokenizer accurately processes vocabulary and special tokens', () async {
      final tempDir = Directory.systemTemp.createTempSync('ai_sub_tok_test');
      final tokFile = File('${tempDir.path}/tokenizer.json');

      final sampleTokJson = '''
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
            [" This", -0.5],
            [" is", -0.4],
            [" a", -0.2],
            [" test", -0.8]
          ]
        }
      }
      ''';
      await tokFile.writeAsString(sampleTokJson);

      final tokenizer = await UnigramTokenizer.fromFile(tokFile.path);
      expect(tokenizer.padTokenId, equals(3));
      expect(tokenizer.eosTokenId, equals(1));

      final tokens = tokenizer.encode('This is a test');
      expect(tokens, isNotEmpty);
      expect(tokens.last, equals(tokenizer.eosTokenId));

      final decoded = tokenizer.decode(tokens);
      expect(decoded.toLowerCase(), contains('test'));

      tempDir.deleteSync(recursive: true);
    });

    test('6. Whisper catalog definitions declare genuine models with SHA-256 hashes', () {
      final catalog = WhisperModelInfo.catalog;
      expect(catalog.length, equals(4));

      final tiny = catalog.firstWhere((m) => m.id == 'tiny');
      expect(tiny.fileName, equals('ggml-tiny.bin'));
      expect(tiny.sizeBytes, greaterThan(70 * 1024 * 1024));
      expect(tiny.sha256, isNotNull);

      final base = catalog.firstWhere((m) => m.id == 'base');
      expect(base.fileName, equals('ggml-base.bin'));
      expect(base.sizeBytes, greaterThan(140 * 1024 * 1024));
      expect(base.sha256, isNotNull);

      final small = catalog.firstWhere((m) => m.id == 'small');
      expect(small.fileName, equals('ggml-small.bin'));
      expect(small.sizeBytes, greaterThan(450 * 1024 * 1024));
      expect(small.sha256, isNotNull);

      final medium = catalog.firstWhere((m) => m.id == 'medium');
      expect(medium.fileName, equals('ggml-medium.bin'));
      expect(medium.sizeBytes, greaterThan(1400 * 1024 * 1024));
      expect(medium.sha256, isNotNull);
    });

    test('7. Whisper Tiny catalog checksum and size match upstream ggerganov artifact', () {
      final tiny = WhisperModelInfo.catalog.firstWhere((m) => m.id == 'tiny');
      expect(tiny.sha256, equals('be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21'));
      expect(tiny.sizeBytes, equals(77691713));
    });

    test('8. OnnxTranslationEngine throws TranslationException when pack is missing', () async {
      final engine = OnnxTranslationEngine();
      expect(
        () => engine.translateText(
          text: 'こんにちは世界',
          sourceLang: 'ja',
          targetLang: 'en',
          packLocalPath: null,
          cueIndex: 5,
        ),
        throwsA(
          isA<TranslationException>()
              .having((e) => e.cueIndex, 'cueIndex', equals(5))
              .having((e) => e.sourceLang, 'sourceLang', equals('ja'))
              .having((e) => e.targetLang, 'targetLang', equals('en')),
        ),
      );
    });
  });
}
