import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import '../../domain/entities/subtitle_cue.dart';
import '../media/wav_utils.dart';

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
    int startChunkIndex = 0,
    List<SubtitleCue>? existingCues,
    Future<void> Function(List<SubtitleCue> newlyGenerated, List<SubtitleCue> allAccumulated)? onCuesGenerated,
    required void Function(double progress, String step) onProgress,
    void Function({
      required double progress,
      required String step,
      int? currentChunk,
      int? totalChunks,
      Duration? elapsed,
      Duration? estimatedRemaining,
      Duration? estimatedTotal,
      Duration? audioDuration,
    })? onDetailedProgress,
    bool Function()? isCancelled,
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
    final totalAudioMs = WavUtils.getDurationMs(audioFile);
    final totalAudioDuration = Duration(milliseconds: totalAudioMs);
    final totalChunks = WavUtils.calculateChunkCount(totalAudioMs);

    if (totalChunks <= 0) {
      return [];
    }

    onProgress(0.2, 'Initializing native Whisper.cpp inference runtime...');

    final whisper = Whisper(
      model: whisperModel,
      modelDir: modelDir,
    );

    // On-demand chunk temporary directory
    final tempDir = await getTemporaryDirectory();
    final chunkDir = Directory('${tempDir.path}/whisper_chunks_${DateTime.now().millisecondsSinceEpoch}');
    if (!await chunkDir.exists()) {
      await chunkDir.create(recursive: true);
    }

    final stopwatch = Stopwatch()..start();
    final List<SubtitleCue> allCues = List<SubtitleCue>.from(existingCues ?? []);
    int cueIndex = allCues.length + 1;
    final safeThreads = threadCount.clamp(1, 4);

    try {
      for (int i = startChunkIndex; i < totalChunks; i++) {
        if (isCancelled?.call() == true) {
          throw Exception('Transcription cancelled by user.');
        }

        final (chunkStartMs, chunkEndMs) = WavUtils.getChunkRange(i, totalAudioMs);
        final completedChunks = i - startChunkIndex;
        final remainingChunks = totalChunks - i;

        Duration? estimatedRemaining;
        Duration? estimatedTotal;
        if (completedChunks > 0) {
          final avgMsPerChunk = stopwatch.elapsedMilliseconds / completedChunks;
          estimatedRemaining = Duration(milliseconds: (avgMsPerChunk * remainingChunks).round());
          estimatedTotal = Duration(milliseconds: stopwatch.elapsedMilliseconds + estimatedRemaining.inMilliseconds);
        }

        final chunkProgress = (i / totalChunks).clamp(0.0, 1.0);
        final startSec = (chunkStartMs / 1000).floor();
        final endSec = (chunkEndMs / 1000).ceil();
        final timeLabel = '${(startSec ~/ 60).toString().padLeft(2, '0')}:${(startSec % 60).toString().padLeft(2, '0')} - ${(endSec ~/ 60).toString().padLeft(2, '0')}:${(endSec % 60).toString().padLeft(2, '0')}';
        final statusMsg = totalChunks > 1
            ? 'Transcribing audio segment ${i + 1} of $totalChunks ($timeLabel)...'
            : 'Running speech recognition inference...';

        onProgress(0.35 + (chunkProgress * 0.50), statusMsg);
        onDetailedProgress?.call(
          progress: chunkProgress,
          step: statusMsg,
          currentChunk: i + 1,
          totalChunks: totalChunks,
          elapsed: stopwatch.elapsed,
          estimatedRemaining: estimatedRemaining,
          estimatedTotal: estimatedTotal,
          audioDuration: totalAudioDuration,
        );

        // Slice ONLY the current chunk on demand to minimize disk usage
        String chunkAudioPath;
        File? chunkFileToClean;
        if (totalChunks == 1) {
          chunkAudioPath = audioFile.path;
        } else {
          final chunkPath = '${chunkDir.path}/chunk_${i + 1}.wav';
          chunkFileToClean = await WavUtils.sliceWav(
            sourceWav: audioFile,
            startMs: chunkStartMs,
            endMs: chunkEndMs,
            outputPath: chunkPath,
          );
          chunkAudioPath = chunkFileToClean.path;
        }

        // Keep elapsed timer live while native inference runs
        Timer? liveTimer;
        liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (isCancelled?.call() == true) {
            liveTimer?.cancel();
            return;
          }
          onDetailedProgress?.call(
            progress: chunkProgress,
            step: statusMsg,
            currentChunk: i + 1,
            totalChunks: totalChunks,
            elapsed: stopwatch.elapsed,
            estimatedRemaining: estimatedRemaining,
            estimatedTotal: estimatedTotal,
            audioDuration: totalAudioDuration,
          );
        });

        WhisperTranscribeResponse response;
        try {
          response = await whisper.transcribe(
            transcribeRequest: TranscribeRequest(
              audio: chunkAudioPath,
              language: language.toLowerCase(),
              threads: safeThreads,
              isTranslate: false,
            ),
          );
        } finally {
          liveTimer.cancel();
          // Immediately delete the chunk file from disk to prevent storage leaks
          if (chunkFileToClean != null) {
            try {
              if (await chunkFileToClean.exists()) {
                await chunkFileToClean.delete();
              }
            } catch (_) {}
          }
        }

        final recognizedText = response.text.trim();
        final segments = response.segments;
        final List<SubtitleCue> chunkCues = [];

        if (segments != null && segments.isNotEmpty) {
          for (final seg in segments) {
            final text = seg.text.trim();
            if (text.isNotEmpty && text != '[BLANK_AUDIO]' && !text.contains('WEBVTT')) {
              final startMs = (seg.fromTs.inMilliseconds + chunkStartMs).clamp(0, totalAudioMs);
              final endMs = (seg.toTs.inMilliseconds + chunkStartMs).clamp(startMs + 400, totalAudioMs);
              chunkCues.add(SubtitleCue(
                projectId: projectId,
                cueIndex: cueIndex++,
                startMs: startMs,
                endMs: endMs,
                text: text,
              ));
            }
          }
        } else if (recognizedText.isNotEmpty && recognizedText != '[BLANK_AUDIO]') {
          chunkCues.add(SubtitleCue(
            projectId: projectId,
            cueIndex: cueIndex++,
            startMs: chunkStartMs,
            endMs: chunkEndMs,
            text: recognizedText,
          ));
        }

        if (chunkCues.isNotEmpty) {
          allCues.addAll(chunkCues);
          // Persist cues incrementally and notify listeners
          await onCuesGenerated?.call(chunkCues, allCues);
        }
      }

      stopwatch.stop();

      if (allCues.isEmpty) {
        throw Exception('No speech detected in the selected audio.');
      }

      onProgress(1.0, 'Speech transcription completed successfully (${allCues.length} cues).');
      onDetailedProgress?.call(
        progress: 1.0,
        step: 'Transcription complete',
        currentChunk: totalChunks,
        totalChunks: totalChunks,
        elapsed: stopwatch.elapsed,
        estimatedRemaining: Duration.zero,
        estimatedTotal: stopwatch.elapsed,
        audioDuration: totalAudioDuration,
      );

      return allCues;
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint('Whisper.cpp native FFI error: $e');
      }

      if (e.toString().contains('No speech detected') || e.toString().contains('cancelled')) {
        rethrow;
      }

      throw Exception('Whisper native speech recognition failed: $e');
    } finally {
      // Clean up temporary audio chunks
      try {
        if (await chunkDir.exists()) {
          await chunkDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}
