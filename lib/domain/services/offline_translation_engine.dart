import '../../native/translation/onnx_translation_engine.dart';
import '../entities/subtitle_cue.dart';

class OfflineTranslationEngine {
  final OnnxTranslationEngine _onnx = OnnxTranslationEngine();

  Future<List<SubtitleCue>> translateCues({
    required List<SubtitleCue> cues,
    required String sourceLang,
    required String targetLang,
    String? packLocalPath,
    required void Function(double progress, String status) onProgress,
  }) async {
    final List<SubtitleCue> translatedList = [];
    final total = cues.length;

    for (int i = 0; i < total; i++) {
      final cue = cues[i];
      final translatedText = await _onnx.translateText(
        text: cue.text,
        sourceLang: sourceLang,
        targetLang: targetLang,
        packLocalPath: packLocalPath,
        cueIndex: cue.cueIndex,
      );

      translatedList.add(cue.copyWith(
        text: translatedText,
        originalText: cue.originalText ?? cue.text,
      ));

      final progress = (i + 1) / total;
      onProgress(progress, 'Translating cue ${i + 1} of $total...');
    }

    return translatedList;
  }
}
