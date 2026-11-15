import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'unigram_tokenizer.dart';

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
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return clean;

    final src = sourceLang == 'auto' ? 'en' : sourceLang.toLowerCase();
    final tgt = targetLang.toLowerCase();
    if (src == tgt) return clean;

    if (packLocalPath == null || !Directory(packLocalPath).existsSync()) {
      throw StateError(
        'Neural language pack for "$src" to "$tgt" is not installed. '
        'Please download it from the Language Packs screen.',
      );
    }

    await loadPack(packLocalPath);

    if (_encoderSession == null || _decoderSession == null || _tokenizer == null) {
      throw StateError('Failed to initialize ONNX sessions for language pack: $packLocalPath');
    }

    return _runSeq2Seq(clean);
  }

  Future<String> _runSeq2Seq(String text) async {
    final tokenizer = _tokenizer!;
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

      // 1. Run Marian / Seq2Seq Encoder
      final encInputs = <String, OrtValue>{
        'input_ids': encInput,
        'attention_mask': encMask,
      };

      encOutputs = _encoderSession!.run(runOptions, encInputs);
      if (encOutputs.isEmpty || encOutputs[0] == null) {
        throw StateError('Encoder produced no output tensor.');
      }
      final encoderHiddenStates = encOutputs[0]!;

      // 2. Autoregressive greedy decoding loop
      final startToken = tokenizer.padTokenId;
      final generatedIds = <int>[startToken];
      final maxLen = min(seqLen * 2 + 15, 128);

      final decInputName = _decoderSession!.inputNames.firstWhere(
        (n) => n.contains('input_ids') || n.contains('decoder'),
        orElse: () => 'input_ids',
      );
      final encHiddenName = _decoderSession!.inputNames.firstWhere(
        (n) => n.contains('hidden_states') || n.contains('encoder'),
        orElse: () => 'encoder_hidden_states',
      );
      final hasEncMask = _decoderSession!.inputNames.any((n) => n.contains('encoder_attention_mask'));

      for (int step = 0; step < maxLen; step++) {
        final decInput = OrtValueTensor.createTensorWithDataList(generatedIds, [1, generatedIds.length]);
        final decInputs = <String, OrtValue>{
          decInputName: decInput,
          encHiddenName: encoderHiddenStates,
        };
        if (hasEncMask) {
          decInputs['encoder_attention_mask'] = encMask;
        }

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
      return translated.isNotEmpty ? translated : text;
    } catch (e) {
      debugPrint('[OnnxTranslationEngine] Inference error on text "$text": $e');
      // Per specification: preserve original dialogue text on cue failure
      return text;
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
