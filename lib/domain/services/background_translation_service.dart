import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../../native/translation/unigram_tokenizer.dart';
import '../entities/subtitle_cue.dart';

sealed class TranslationEvent {}

class TranslationProgressEvent extends TranslationEvent {
  final int completedCues;
  final int totalCues;
  final int failedCues;
  final SubtitleCue? lastTranslatedCue;
  final Duration elapsed;
  final Duration? estimatedRemaining;

  TranslationProgressEvent({
    required this.completedCues,
    required this.totalCues,
    required this.failedCues,
    this.lastTranslatedCue,
    required this.elapsed,
    this.estimatedRemaining,
  });
}

class TranslationFinishedEvent extends TranslationEvent {
  final List<SubtitleCue> cues;
  final int successCount;
  final int failedCount;

  TranslationFinishedEvent({
    required this.cues,
    required this.successCount,
    required this.failedCount,
  });
}

class TranslationErrorEvent extends TranslationEvent {
  final String error;
  TranslationErrorEvent(this.error);
}

class _WorkerParams {
  final SendPort sendPort;
  final List<Map<String, dynamic>> rawCues;
  final String sourceLang;
  final String targetLang;
  final String packLocalPath;
  final List<int>? retryCueIndexes;

  const _WorkerParams({
    required this.sendPort,
    required this.rawCues,
    required this.sourceLang,
    required this.targetLang,
    required this.packLocalPath,
    this.retryCueIndexes,
  });
}

class BackgroundTranslationHandle {
  final Stream<TranslationEvent> stream;
  final VoidCallback cancel;

  const BackgroundTranslationHandle({
    required this.stream,
    required this.cancel,
  });
}

class BackgroundTranslationService {
  static BackgroundTranslationHandle translateCues({
    required List<SubtitleCue> cues,
    required String sourceLang,
    required String targetLang,
    required String packLocalPath,
    List<int>? retryCueIndexes,
  }) {
    final controller = StreamController<TranslationEvent>.broadcast();
    final receivePort = ReceivePort();
    Isolate? isolate;
    SendPort? controlPort;
    bool isCancelled = false;

    void cancel() {
      if (isCancelled) return;
      isCancelled = true;
      try {
        controlPort?.send('cancel');
        isolate?.kill(priority: Isolate.immediate);
      } catch (_) {}
      receivePort.close();
      if (!controller.isClosed) {
        controller.close();
      }
    }

    final rawCues = cues.map((c) => c.toMap()).toList();
    final params = _WorkerParams(
      sendPort: receivePort.sendPort,
      rawCues: rawCues,
      sourceLang: sourceLang,
      targetLang: targetLang,
      packLocalPath: packLocalPath,
      retryCueIndexes: retryCueIndexes,
    );

    Isolate.spawn<_WorkerParams>(_workerEntryPoint, params).then((spawnedIsolate) {
      isolate = spawnedIsolate;
    }).catchError((err) {
      if (!controller.isClosed) {
        controller.add(TranslationErrorEvent('Failed to spawn translation worker: $err'));
        controller.close();
      }
      receivePort.close();
    });

    receivePort.listen((message) {
      if (message is SendPort) {
        controlPort = message;
      } else if (message is Map<String, dynamic>) {
        final type = message['type'] as String?;
        if (type == 'progress') {
          final cueMap = message['lastCue'] as Map<String, dynamic>?;
          final cue = cueMap != null ? SubtitleCue.fromMap(cueMap) : null;
          final elapsedMs = message['elapsedMs'] as int? ?? 0;
          final etaMs = message['etaMs'] as int?;
          if (!controller.isClosed) {
            controller.add(TranslationProgressEvent(
              completedCues: message['completed'] as int? ?? 0,
              totalCues: message['total'] as int? ?? 0,
              failedCues: message['failed'] as int? ?? 0,
              lastTranslatedCue: cue,
              elapsed: Duration(milliseconds: elapsedMs),
              estimatedRemaining: etaMs != null ? Duration(milliseconds: etaMs) : null,
            ));
          }
        } else if (type == 'finished') {
          final listMaps = message['cues'] as List<dynamic>? ?? [];
          final listCues = listMaps.map((m) => SubtitleCue.fromMap(m as Map<String, dynamic>)).toList();
          if (!controller.isClosed) {
            controller.add(TranslationFinishedEvent(
              cues: listCues,
              successCount: message['success'] as int? ?? 0,
              failedCount: message['failed'] as int? ?? 0,
            ));
            controller.close();
          }
          receivePort.close();
        } else if (type == 'error') {
          if (!controller.isClosed) {
            controller.add(TranslationErrorEvent(message['error'] as String? ?? 'Unknown worker error'));
            controller.close();
          }
          receivePort.close();
        }
      }
    }, onDone: () {
      if (!controller.isClosed) controller.close();
    });

    return BackgroundTranslationHandle(
      stream: controller.stream,
      cancel: cancel,
    );
  }

  static void _workerEntryPoint(_WorkerParams params) async {
    final controlPort = ReceivePort();
    params.sendPort.send(controlPort.sendPort);

    bool cancelRequested = false;
    controlPort.listen((msg) {
      if (msg == 'cancel') {
        cancelRequested = true;
      }
    });

    final packDir = params.packLocalPath;
    final encoderFile = File('$packDir/encoder_model_quantized.onnx');
    final decoderFile = File('$packDir/decoder_model_quantized.onnx');
    final tokenizerFile = File('$packDir/tokenizer.json');

    if (!encoderFile.existsSync() || !decoderFile.existsSync() || !tokenizerFile.existsSync()) {
      params.sendPort.send({
        'type': 'error',
        'error': 'Neural language pack files not found at: $packDir',
      });
      return;
    }

    OrtSessionOptions? sessionOptions;
    OrtSession? encoderSession;
    OrtSession? decoderSession;
    UnigramTokenizer? tokenizer;

    try {
      OrtEnv.instance.init();
      sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(1)
        ..setIntraOpNumThreads(2)
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

      encoderSession = OrtSession.fromFile(encoderFile, sessionOptions);
      decoderSession = OrtSession.fromFile(decoderFile, sessionOptions);
      tokenizer = await UnigramTokenizer.fromFile(tokenizerFile.path);
    } catch (e) {
      params.sendPort.send({
        'type': 'error',
        'error': 'Failed to initialize ONNX sessions: $e',
      });
      return;
    }

    final totalCues = params.rawCues.length;
    final stopwatch = Stopwatch()..start();
    final List<Map<String, dynamic>> results = [];
    int successCount = 0;
    int failedCount = 0;
    final retrySet = params.retryCueIndexes?.toSet();

    for (int i = 0; i < totalCues; i++) {
      if (cancelRequested) break;

      final cueMap = params.rawCues[i];
      final cue = SubtitleCue.fromMap(cueMap);

      if (retrySet != null && !retrySet.contains(cue.cueIndex)) {
        // Skip if not in retry set
        results.add(cueMap);
        continue;
      }

      final text = cue.text.trim();
      if (text.isEmpty) {
        results.add(cueMap);
        continue;
      }

      Map<String, dynamic>? updatedCueMap;
      try {
        final translatedText = _translateTextInWorker(
          text: text,
          sourceLang: params.sourceLang,
          targetLang: params.targetLang,
          tokenizer: tokenizer,
          encoderSession: encoderSession,
          decoderSession: decoderSession,
        );

        final updatedCue = cue.copyWith(
          text: translatedText,
          originalText: cue.originalText ?? cue.text,
        );
        updatedCueMap = updatedCue.toMap();
        results.add(updatedCueMap);
        successCount++;
      } catch (err) {
        failedCount++;
        // Preserve original cue on failure
        results.add(cueMap);
        if (kDebugMode) {
          debugPrint('Worker translation error on cue #${cue.cueIndex}: $err');
        }
      }

      // Calculate ETA
      final elapsedMs = stopwatch.elapsedMilliseconds;
      int? etaMs;
      if (successCount + failedCount > 0) {
        final avgMs = elapsedMs / (successCount + failedCount);
        final remaining = totalCues - (successCount + failedCount);
        etaMs = (avgMs * remaining).round();
      }

      params.sendPort.send({
        'type': 'progress',
        'completed': successCount + failedCount,
        'total': totalCues,
        'failed': failedCount,
        'lastCue': updatedCueMap,
        'elapsedMs': elapsedMs,
        'etaMs': etaMs,
      });
    }

    stopwatch.stop();

    try {
      encoderSession.release();
      decoderSession.release();
      sessionOptions.release();
    } catch (_) {}

    params.sendPort.send({
      'type': 'finished',
      'cues': results,
      'success': successCount,
      'failed': failedCount,
    });
  }

  static String _translateTextInWorker({
    required String text,
    required String sourceLang,
    required String targetLang,
    required UnigramTokenizer tokenizer,
    required OrtSession encoderSession,
    required OrtSession decoderSession,
  }) {
    final clean = text.trim();
    if (clean.isEmpty) return clean;

    final src = sourceLang == 'auto' ? 'en' : sourceLang.toLowerCase();
    final tgt = targetLang.toLowerCase();
    if (src == tgt) return clean;

    // Mixed-language segmentation
    final segments = _segmentDialogue(clean, src, tgt);
    if (segments.length == 1 && segments[0].isSource) {
      return _runSeq2SeqInWorker(
        text: clean,
        tokenizer: tokenizer,
        encoderSession: encoderSession,
        decoderSession: decoderSession,
      );
    }

    final translatedParts = <String>[];
    for (final seg in segments) {
      if (seg.isSource) {
        final part = _runSeq2SeqInWorker(
          text: seg.text,
          tokenizer: tokenizer,
          encoderSession: encoderSession,
          decoderSession: decoderSession,
        );
        translatedParts.add(part);
      } else {
        translatedParts.add(seg.text);
      }
    }

    return _stitch(translatedParts);
  }

  static String _runSeq2SeqInWorker({
    required String text,
    required UnigramTokenizer tokenizer,
    required OrtSession encoderSession,
    required OrtSession decoderSession,
  }) {
    final inputTokens = tokenizer.encode(text);
    if (inputTokens.isEmpty) return text;

    final runOptions = OrtRunOptions();
    OrtValueTensor? encInput;
    OrtValueTensor? encMask;
    List<OrtValue?>? encOutputs;

    try {
      final seqLen = inputTokens.length;
      final encShape = [1, seqLen];
      encInput = OrtValueTensor.createTensorWithDataList(inputTokens, encShape);
      encMask = OrtValueTensor.createTensorWithDataList(List.filled(seqLen, 1), encShape);

      final encInputs = <String, OrtValue>{
        'input_ids': encInput,
        'attention_mask': encMask,
      };

      encOutputs = encoderSession.run(runOptions, encInputs);
      if (encOutputs.isEmpty || encOutputs[0] == null) {
        return text;
      }
      final encoderHiddenStates = encOutputs[0]!;

      final startToken = tokenizer.padTokenId;
      final generatedIds = <int>[startToken];
      final maxLen = min(seqLen * 3 + 20, 128);

      for (int step = 0; step < maxLen; step++) {
        final decInput = OrtValueTensor.createTensorWithDataList(generatedIds, [1, generatedIds.length]);
        final decInputs = <String, OrtValue>{
          'input_ids': decInput,
          'encoder_hidden_states': encoderHiddenStates,
          'encoder_attention_mask': encMask,
        };

        final decOutputs = decoderSession.run(runOptions, decInputs);
        decInput.release();

        if (decOutputs.isEmpty || decOutputs[0] == null) {
          break;
        }

        final logitsVal = decOutputs[0]!.value;
        decOutputs[0]!.release();

        int bestId = tokenizer.eosTokenId;
        if (logitsVal is List && logitsVal.isNotEmpty) {
          final batch0 = logitsVal[0];
          if (batch0 is List && batch0.isNotEmpty) {
            final lastStep = batch0.last;
            if (lastStep is List) {
              double maxLogit = -double.infinity;
              for (int id = 0; id < lastStep.length; id++) {
                if (id == tokenizer.padTokenId || id == tokenizer.unkTokenId) {
                  continue;
                }
                final logit = (lastStep[id] as num).toDouble();
                if (logit > maxLogit) {
                  maxLogit = logit;
                  bestId = id;
                }
              }
            }
          }
        }

        if (bestId == tokenizer.eosTokenId) {
          break;
        }

        generatedIds.add(bestId);
      }

      runOptions.release();

      final outputIds = generatedIds.where((id) => id != tokenizer.padTokenId && id != tokenizer.eosTokenId).toList();
      if (outputIds.isEmpty) {
        return text;
      }

      final translated = tokenizer.decode(outputIds).trim();
      return translated.isNotEmpty ? translated : text;
    } catch (_) {
      return text;
    } finally {
      encInput?.release();
      encMask?.release();
      if (encOutputs != null) {
        for (final v in encOutputs) {
          v?.release();
        }
      }
    }
  }

  static List<({String text, bool isSource})> _segmentDialogue(String text, String srcLang, String tgtLang) {
    if (srcLang == 'ja' || srcLang == 'zh' || srcLang == 'ko') {
      final foreignScriptRegex = RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff66-\uff9f\uac00-\ud7af]');
      final tokens = text.split(' ');
      final List<({String text, bool isSource})> segments = [];
      String currentBuffer = '';
      bool? currentIsSource;

      for (final token in tokens) {
        final hasForeign = foreignScriptRegex.hasMatch(token);
        if (currentIsSource == null) {
          currentIsSource = hasForeign;
          currentBuffer = token;
        } else if (currentIsSource == hasForeign) {
          currentBuffer += ' $token';
        } else {
          segments.add((text: currentBuffer, isSource: currentIsSource));
          currentBuffer = token;
          currentIsSource = hasForeign;
        }
      }
      if (currentBuffer.isNotEmpty && currentIsSource != null) {
        segments.add((text: currentBuffer, isSource: currentIsSource));
      }
      return segments.isNotEmpty ? segments : [(text: text, isSource: true)];
    }
    return [(text: text, isSource: true)];
  }

  static String _stitch(List<String> parts) {
    final buffer = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      if (part.isEmpty) continue;
      if (buffer.isNotEmpty) {
        final lastChar = buffer.toString()[buffer.length - 1];
        if (lastChar != ' ' && !RegExp(r'[,.:;?!]').hasMatch(part[0])) {
          buffer.write(' ');
        }
      }
      buffer.write(part);
    }
    return buffer.toString()
        .replaceAll(RegExp(r'\s+([,.:;?!])'), r'$1')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
