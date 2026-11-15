import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import '../../core/utilities/timestamp_utils.dart';
import '../../domain/entities/subtitle_cue.dart';

class WhisperEngine {
  static final WhisperEngine _instance = WhisperEngine._internal();
  factory WhisperEngine() => _instance;
  WhisperEngine._internal();

  /// Transcribes 16kHz mono audio file using genuine on-device Whisper.cpp native inference.
  Future<List<SubtitleCue>> transcribe({
    required String audioPath,
    required String modelPath,
    required String projectId,
    String language = 'auto',
    int threadCount = 4,
    required void Function(double progress, String step) onProgress,
  }) async {
    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      throw Exception('Audio file not found: $audioPath');
    }

    if (modelPath.isEmpty || !await File(modelPath).exists()) {
      throw Exception(
        'Speech model file not found at: $modelPath. Please download a model from Model Library before transcribing.',
      );
    }

    onProgress(0.1, 'Configuring Whisper.cpp native model...');

    // Determine model type from file path
    final fileName = File(modelPath).uri.pathSegments.last.toLowerCase();
    WhisperModel whisperModel = WhisperModel.base;
    if (fileName.contains('tiny')) {
      whisperModel = WhisperModel.tiny;
    } else if (fileName.contains('base')) {
      whisperModel = WhisperModel.base;
    } else if (fileName.contains('small')) {
      whisperModel = WhisperModel.small;
    } else if (fileName.contains('medium')) {
      whisperModel = WhisperModel.medium;
    } else if (fileName.contains('large-v1')) {
      whisperModel = WhisperModel.largeV1;
    } else if (fileName.contains('large')) {
      whisperModel = WhisperModel.largeV2;
    }

    final modelDir = File(modelPath).parent.path;

    onProgress(0.2, 'Initializing native Whisper.cpp inference runtime...');

    // 1. Try official native Whisper.cpp FFI bindings via whisper_flutter_new
    try {
      final whisper = Whisper(
        model: whisperModel,
        modelDir: modelDir,
      );

      onProgress(0.35, 'Running speech recognition inference on $audioPath...');

      final response = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioPath,
          language: language.toLowerCase(),
          threads: threadCount,
          isTranslate: false,
        ),
      );

      onProgress(0.85, 'Extracting recognized speech segments and timestamps...');

      final recognizedText = response.text.trim();
      final segments = response.segments;

      if ((segments == null || segments.isEmpty) && recognizedText.isEmpty) {
        throw Exception('No speech detected in the selected audio.');
      }

      final List<SubtitleCue> cues = [];
      int cueIndex = 1;

      if (segments != null && segments.isNotEmpty) {
        for (final seg in segments) {
          final text = seg.text.trim();
          if (text.isNotEmpty) {
            cues.add(SubtitleCue(
              projectId: projectId,
              cueIndex: cueIndex++,
              startMs: seg.fromTs.inMilliseconds,
              endMs: seg.toTs.inMilliseconds,
              text: text,
            ));
          }
        }
      }

      // If segments list is empty but overall text was recognized, package as single cue
      if (cues.isEmpty && recognizedText.isNotEmpty) {
        cues.add(SubtitleCue(
          projectId: projectId,
          cueIndex: 1,
          startMs: 0,
          endMs: 5000,
          text: recognizedText,
        ));
      }

      if (cues.isEmpty) {
        throw Exception('No speech detected in the selected audio.');
      }

      onProgress(1.0, 'Speech transcription completed successfully (${cues.length} cues).');
      return cues;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('whisper_flutter_new error: $e');
      }

      if (e.toString().contains('No speech detected')) {
        rethrow;
      }

      // 2. Fallback: try whisper-cli if available in system PATH (desktop development/CLI builds)
      try {
        final cliResult = await Process.run('whisper-cli', [
          '-m', modelPath,
          '-f', audioPath,
          '-l', language.toLowerCase(),
          '-t', threadCount.toString(),
          '--output-srt',
        ]);

        if (cliResult.exitCode == 0) {
          final srtFile = File('$audioPath.srt');
          if (await srtFile.exists()) {
            final content = await srtFile.readAsString();
            final cues = _parseGeneratedSrt(content, projectId);
            await srtFile.delete();
            if (cues.isNotEmpty) {
              onProgress(1.0, 'Speech transcription completed via whisper-cli (${cues.length} cues).');
              return cues;
            }
          }
        }
      } catch (_) {}

      // If both fail, fail with the genuine native exception message
      throw Exception('Whisper speech recognition failed: $e');
    }
  }

  static List<SubtitleCue> _parseGeneratedSrt(String content, String projectId) {
    final List<SubtitleCue> cues = [];
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    int cueIndex = 0;
    int? startMs;
    int? endMs;
    final List<String> textLines = [];

    void commit() {
      if (startMs != null && endMs != null && textLines.isNotEmpty) {
        cueIndex++;
        cues.add(SubtitleCue(
          projectId: projectId,
          cueIndex: cueIndex,
          startMs: startMs!,
          endMs: endMs!,
          text: textLines.join('\n').trim(),
        ));
      }
      startMs = null;
      endMs = null;
      textLines.clear();
    }

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) {
        commit();
        continue;
      }
      if (t.contains('-->')) {
        final parts = t.split('-->');
        startMs = TimestampUtils.parseSrt(parts[0]);
        endMs = TimestampUtils.parseSrt(parts[1]);
        continue;
      }
      if (startMs == null && int.tryParse(t) != null) continue;
      if (startMs != null && endMs != null) textLines.add(t);
    }
    commit();
    return cues;
  }
}
