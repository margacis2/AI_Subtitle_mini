import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'unigram_tokenizer.dart';

class TranslationException implements Exception {
  final String message;
  final String sourceLang;
  final String targetLang;
  final int? cueIndex;

  TranslationException({
    required this.message,
    required this.sourceLang,
    required this.targetLang,
    this.cueIndex,
  });

  @override
  String toString() {
    final cueStr = cueIndex != null ? ' (cue #$cueIndex)' : '';
    return 'TranslationException[$sourceLang->$targetLang]$cueStr: $message';
  }
}

class OnnxTranslationEngine {
  static final OnnxTranslationEngine _instance = OnnxTranslationEngine._internal();
  factory OnnxTranslationEngine() => _instance;
  OnnxTranslationEngine._internal();

  bool _ortInitialized = false;
  String? _loadedPackPath;
  OrtSession? _encoderSession;
  OrtSession? _decoderSession;
  UnigramTokenizer? _tokenizer;
  OrtSessionOptions? _sessionOptions;

  void _ensureOrt() {
    if (!_ortInitialized) {
      try {
        OrtEnv.instance.init();
        _ortInitialized = true;
      } catch (e) {
        debugPrint('[OnnxTranslationEngine] OrtEnv init warning: $e');
      }
    }
  }

  Future<void> loadPack(String packDir) async {
    if (_loadedPackPath == packDir && _encoderSession != null && _decoderSession != null && _tokenizer != null) {
      return;
    }

    _ensureOrt();
    _releaseSessions();

    final encoderFile = File('$packDir/encoder_model_quantized.onnx');
    final decoderFile = File('$packDir/decoder_model_quantized.onnx');
    final tokenizerFile = File('$packDir/tokenizer.json');

    if (!await encoderFile.exists() || !await decoderFile.exists()) {
      throw FileSystemException(
        'Neural model files not found in $packDir. Ensure the language pack is fully downloaded.',
        encoderFile.path,
      );
    }

    _sessionOptions = OrtSessionOptions()
      ..setInterOpNumThreads(1)
      ..setIntraOpNumThreads(2)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

    _encoderSession = OrtSession.fromFile(encoderFile, _sessionOptions!);
    _decoderSession = OrtSession.fromFile(decoderFile, _sessionOptions!);
    _tokenizer = await UnigramTokenizer.fromFile(tokenizerFile.path);
    _loadedPackPath = packDir;
  }

  void _releaseSessions() {
    try {
      _encoderSession?.release();
      _encoderSession = null;
      _decoderSession?.release();
      _decoderSession = null;
      _sessionOptions?.release();
      _sessionOptions = null;
      _tokenizer = null;
      _loadedPackPath = null;
    } catch (e) {
      debugPrint('[OnnxTranslationEngine] Release sessions error: $e');
    }
  }

  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
    String? packLocalPath,
    int? cueIndex,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return clean;

    final src = sourceLang == 'auto' ? 'en' : sourceLang.toLowerCase();
    final tgt = targetLang.toLowerCase();
    if (src == tgt) return clean;

    if (packLocalPath == null || !Directory(packLocalPath).existsSync()) {
      throw TranslationException(
        message: 'Neural language pack is not installed locally. Please download it from Language Packs.',
        sourceLang: src,
        targetLang: tgt,
        cueIndex: cueIndex,
      );
    }

    await loadPack(packLocalPath);

    if (_encoderSession == null || _decoderSession == null || _tokenizer == null) {
      throw TranslationException(
        message: 'Failed to initialize ONNX runtime sessions for pack: $packLocalPath',
        sourceLang: src,
        targetLang: tgt,
        cueIndex: cueIndex,
      );
    }

    return _runSeq2Seq(
      text: clean,
      sourceLang: src,
      targetLang: tgt,
      cueIndex: cueIndex,
    );
  }

  Future<String> _runSeq2Seq({
    required String text,
    required String sourceLang,
    required String targetLang,
    int? cueIndex,
  }) async {
    final tokenizer = _tokenizer!;
    final inputTokens = tokenizer.encode(text);
    if (inputTokens.isEmpty) {
      throw TranslationException(
        message: 'Tokenizer failed to produce valid input tokens for text: "$text"',
        sourceLang: sourceLang,
        targetLang: targetLang,
        cueIndex: cueIndex,
      );
    }

    final runOptions = OrtRunOptions();
    OrtValueTensor? encInput;
    OrtValueTensor? encMask;
    List<OrtValue?>? encOutputs;

    try {
      final seqLen = inputTokens.length;
      final encShape = [1, seqLen];
      encInput = OrtValueTensor.createTensorWithDataList(inputTokens, encShape);
      encMask = OrtValueTensor.createTensorWithDataList(List.filled(seqLen, 1), encShape);

      // 1. Run Marian / Seq2Seq Encoder
      final encInputs = <String, OrtValue>{
        'input_ids': encInput,
        'attention_mask': encMask,
      };

      encOutputs = _encoderSession!.run(runOptions, encInputs);
      if (encOutputs.isEmpty || encOutputs[0] == null) {
        throw TranslationException(
          message: 'Encoder produced no output tensor.',
          sourceLang: sourceLang,
          targetLang: targetLang,
          cueIndex: cueIndex,
        );
      }
      final encoderHiddenStates = encOutputs[0]!;

      // 2. Autoregressive greedy decoding loop
      final startToken = tokenizer.padTokenId;
      final generatedIds = <int>[startToken];
      final maxLen = min(seqLen * 2 + 20, 128);

      for (int step = 0; step < maxLen; step++) {
        final decInput = OrtValueTensor.createTensorWithDataList(generatedIds, [1, generatedIds.length]);
        final decInputs = <String, OrtValue>{
          'input_ids': decInput,
          'encoder_hidden_states': encoderHiddenStates,
          'encoder_attention_mask': encMask,
        };

        final decOutputs = _decoderSession!.run(runOptions, decInputs);
        decInput.release();

        if (decOutputs.isEmpty || decOutputs[0] == null) {
          break;
        }

        final logitsVal = decOutputs[0]!.value;
        decOutputs[0]!.release();

        // Extract last token logits: shape [1, step + 1, vocab_size]
        int bestId = tokenizer.eosTokenId;
        if (logitsVal is List && logitsVal.isNotEmpty) {
          final batch0 = logitsVal[0];
          if (batch0 is List && batch0.isNotEmpty) {
            final lastStep = batch0.last;
            if (lastStep is List) {
              double maxLogit = -double.infinity;
              for (int v = 0; v < lastStep.length; v++) {
                final logit = (lastStep[v] as num).toDouble();
                if (logit > maxLogit) {
                  maxLogit = logit;
                  bestId = v;
                }
              }
            }
          }
        }

        if (bestId == tokenizer.eosTokenId || bestId == tokenizer.padTokenId) {
          break;
        }

        generatedIds.add(bestId);
      }

      // Decode generated token IDs skipping start token
      final resultTokens = generatedIds.skip(1).toList();
      final translated = tokenizer.decode(resultTokens);

      if (translated.isEmpty) {
        throw TranslationException(
          message: 'Neural model produced empty translation for dialogue: "$text"',
          sourceLang: sourceLang,
          targetLang: targetLang,
          cueIndex: cueIndex,
        );
      }

      // Detect obvious source passthrough when translating between different language scripts
      if (sourceLang == 'ja' && targetLang == 'en') {
        final hasJapanese = RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]').hasMatch(translated);
        final hasLatin = RegExp(r'[a-zA-Z]').hasMatch(translated);
        if (hasJapanese && !hasLatin) {
          throw TranslationException(
            message: 'Inference failed to translate Japanese dialogue to English: "$translated"',
            sourceLang: sourceLang,
            targetLang: targetLang,
            cueIndex: cueIndex,
          );
        }
      }

      return translated;
    } catch (e) {
      if (e is TranslationException) {
        rethrow;
      }
      throw TranslationException(
        message: 'ONNX inference error on "$text": $e',
        sourceLang: sourceLang,
        targetLang: targetLang,
        cueIndex: cueIndex,
      );
    } finally {
      encInput?.release();
      encMask?.release();
      if (encOutputs != null) {
        for (final o in encOutputs) {
          o?.release();
        }
      }
      runOptions.release();
    }
  }

  void dispose() {
    _releaseSessions();
  }
}
