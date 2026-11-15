import 'package:equatable/equatable.dart';

class TranslationPackInfo extends Equatable {
  final String id;
  final String sourceLang;
  final String targetLang;
  final String displayName;
  final String provider;
  final String modelType;
  final int totalSizeBytes;
  final String encoderUrl;
  final String decoderUrl;
  final String tokenizerUrl;
  final String description;
  final bool isInstalled;
  final String? localPath;

  const TranslationPackInfo({
    required this.id,
    required this.sourceLang,
    required this.targetLang,
    required this.displayName,
    required this.provider,
    required this.modelType,
    required this.totalSizeBytes,
    required this.encoderUrl,
    required this.decoderUrl,
    required this.tokenizerUrl,
    required this.description,
    this.isInstalled = false,
    this.localPath,
  });

  String get formattedSize {
    final mb = totalSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  TranslationPackInfo copyWith({
    String? id,
    String? sourceLang,
    String? targetLang,
    String? displayName,
    String? provider,
    String? modelType,
    int? totalSizeBytes,
    String? encoderUrl,
    String? decoderUrl,
    String? tokenizerUrl,
    String? description,
    bool? isInstalled,
    String? localPath,
  }) {
    return TranslationPackInfo(
      id: id ?? this.id,
      sourceLang: sourceLang ?? this.sourceLang,
      targetLang: targetLang ?? this.targetLang,
      displayName: displayName ?? this.displayName,
      provider: provider ?? this.provider,
      modelType: modelType ?? this.modelType,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      encoderUrl: encoderUrl ?? this.encoderUrl,
      decoderUrl: decoderUrl ?? this.decoderUrl,
      tokenizerUrl: tokenizerUrl ?? this.tokenizerUrl,
      description: description ?? this.description,
      isInstalled: isInstalled ?? this.isInstalled,
      localPath: localPath ?? this.localPath,
    );
  }

  static const List<TranslationPackInfo> catalog = [
    TranslationPackInfo(
      id: 'opus-mt-ja-en',
      sourceLang: 'ja',
      targetLang: 'en',
      displayName: 'Japanese to English',
      provider: 'Tiedemann & Thottingal (OPUS-MT) / University of Helsinki',
      modelType: 'ONNX INT8 Quantized (Marian Seq2Seq)',
      totalSizeBytes: 79000000, // ~79 MB
      encoderUrl: 'https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/onnx/encoder_model_quantized.onnx',
      decoderUrl: 'https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/onnx/decoder_model_quantized.onnx',
      tokenizerUrl: 'https://huggingface.co/Xenova/opus-mt-ja-en/raw/main/tokenizer.json',
      description: 'High-speed offline neural translation for anime, dramas, news, and conversations.',
    ),
    TranslationPackInfo(
      id: 'opus-mt-ko-en',
      sourceLang: 'ko',
      targetLang: 'en',
      displayName: 'Korean to English',
      provider: 'Tiedemann & Thottingal (OPUS-MT) / University of Helsinki',
      modelType: 'ONNX INT8 Quantized (Marian Seq2Seq)',
      totalSizeBytes: 77000000, // ~77 MB
      encoderUrl: 'https://huggingface.co/Xenova/opus-mt-ko-en/resolve/main/onnx/encoder_model_quantized.onnx',
      decoderUrl: 'https://huggingface.co/Xenova/opus-mt-ko-en/resolve/main/onnx/decoder_model_quantized.onnx',
      tokenizerUrl: 'https://huggingface.co/Xenova/opus-mt-ko-en/raw/main/tokenizer.json',
      description: 'Specialized neural model for Korean television series, films, and podcasts.',
    ),
    TranslationPackInfo(
      id: 'opus-mt-hi-en',
      sourceLang: 'hi',
      targetLang: 'en',
      displayName: 'Hindi to English',
      provider: 'Tiedemann & Thottingal (OPUS-MT) / University of Helsinki',
      modelType: 'ONNX INT8 Quantized (Marian Seq2Seq)',
      totalSizeBytes: 76000000, // ~76 MB
      encoderUrl: 'https://huggingface.co/Xenova/opus-mt-hi-en/resolve/main/onnx/encoder_model_quantized.onnx',
      decoderUrl: 'https://huggingface.co/Xenova/opus-mt-hi-en/resolve/main/onnx/decoder_model_quantized.onnx',
      tokenizerUrl: 'https://huggingface.co/Xenova/opus-mt-hi-en/raw/main/tokenizer.json',
      description: 'Translates spoken Hindi dialogue into natural English subtitles using sequence-to-sequence neural inference.',
    ),
    TranslationPackInfo(
      id: 'opus-mt-en-hi',
      sourceLang: 'en',
      targetLang: 'hi',
      displayName: 'English to Hindi',
      provider: 'Tiedemann & Thottingal (OPUS-MT) / University of Helsinki',
      modelType: 'ONNX INT8 Quantized (Marian Seq2Seq)',
      totalSizeBytes: 78000000, // ~78 MB
      encoderUrl: 'https://huggingface.co/Xenova/opus-mt-en-hi/resolve/main/onnx/encoder_model_quantized.onnx',
      decoderUrl: 'https://huggingface.co/Xenova/opus-mt-en-hi/resolve/main/onnx/decoder_model_quantized.onnx',
      tokenizerUrl: 'https://huggingface.co/Xenova/opus-mt-en-hi/raw/main/tokenizer.json',
      description: 'Translates English movies, videos, and speeches into Hindi subtitle tracks.',
    ),
    TranslationPackInfo(
      id: 'opus-mt-en-es',
      sourceLang: 'en',
      targetLang: 'es',
      displayName: 'English to Spanish',
      provider: 'Tiedemann & Thottingal (OPUS-MT) / University of Helsinki',
      modelType: 'ONNX INT8 Quantized (Marian Seq2Seq)',
      totalSizeBytes: 76000000, // ~76 MB
      encoderUrl: 'https://huggingface.co/Xenova/opus-mt-en-es/resolve/main/onnx/encoder_model_quantized.onnx',
      decoderUrl: 'https://huggingface.co/Xenova/opus-mt-en-es/resolve/main/onnx/decoder_model_quantized.onnx',
      tokenizerUrl: 'https://huggingface.co/Xenova/opus-mt-en-es/raw/main/tokenizer.json',
      description: 'Translates English dialogue into natural Spanish subtitle tracks.',
    ),
    TranslationPackInfo(
      id: 'opus-mt-en-fr',
      sourceLang: 'en',
      targetLang: 'fr',
      displayName: 'English to French',
      provider: 'Tiedemann & Thottingal (OPUS-MT) / University of Helsinki',
      modelType: 'ONNX INT8 Quantized (Marian Seq2Seq)',
      totalSizeBytes: 77000000, // ~77 MB
      encoderUrl: 'https://huggingface.co/Xenova/opus-mt-en-fr/resolve/main/onnx/encoder_model_quantized.onnx',
      decoderUrl: 'https://huggingface.co/Xenova/opus-mt-en-fr/resolve/main/onnx/decoder_model_quantized.onnx',
      tokenizerUrl: 'https://huggingface.co/Xenova/opus-mt-en-fr/raw/main/tokenizer.json',
      description: 'Translates English dialogue into idiomatic French subtitles.',
    ),
    TranslationPackInfo(
      id: 'opus-mt-en-de',
      sourceLang: 'en',
      targetLang: 'de',
      displayName: 'English to German',
      provider: 'Tiedemann & Thottingal (OPUS-MT) / University of Helsinki',
      modelType: 'ONNX INT8 Quantized (Marian Seq2Seq)',
      totalSizeBytes: 78000000, // ~78 MB
      encoderUrl: 'https://huggingface.co/Xenova/opus-mt-en-de/resolve/main/onnx/encoder_model_quantized.onnx',
      decoderUrl: 'https://huggingface.co/Xenova/opus-mt-en-de/resolve/main/onnx/decoder_model_quantized.onnx',
      tokenizerUrl: 'https://huggingface.co/Xenova/opus-mt-en-de/raw/main/tokenizer.json',
      description: 'Translates English dialogue into accurate German subtitles.',
    ),
    TranslationPackInfo(
      id: 'opus-mt-en-ja',
      sourceLang: 'en',
      targetLang: 'ja',
      displayName: 'English to Japanese',
      provider: 'Tiedemann & Thottingal (OPUS-MT) / University of Helsinki',
      modelType: 'ONNX INT8 Quantized (Marian Seq2Seq)',
      totalSizeBytes: 78000000, // ~78 MB
      encoderUrl: 'https://huggingface.co/Xenova/opus-mt-en-jap/resolve/main/onnx/encoder_model_quantized.onnx',
      decoderUrl: 'https://huggingface.co/Xenova/opus-mt-en-jap/resolve/main/onnx/decoder_model_quantized.onnx',
      tokenizerUrl: 'https://huggingface.co/Xenova/opus-mt-en-jap/raw/main/tokenizer.json',
      description: 'Translates English dialogue into natural Japanese subtitles.',
    ),
    TranslationPackInfo(
      id: 'nllb-200-600m',
      sourceLang: 'ta',
      targetLang: 'en',
      displayName: 'Tamil / Multilingual to English (NLLB)',
      provider: 'Meta AI / Xenova (ONNX Runtime)',
      modelType: 'ONNX INT8 Quantized (NLLB-200 Distilled 600M)',
      totalSizeBytes: 310000000, // ~310 MB
      encoderUrl: 'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/onnx/encoder_model_quantized.onnx',
      decoderUrl: 'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/onnx/decoder_model_merged_quantized.onnx',
      tokenizerUrl: 'https://huggingface.co/Xenova/nllb-200-distilled-600M/raw/main/tokenizer.json',
      description: 'Dedicated pairwise OPUS-MT ONNX model is not published upstream on Hugging Face. Tamil neural translation is available via the NLLB-200 Multilingual model.',
    ),
  ];

  @override
  List<Object?> get props => [
        id,
        sourceLang,
        targetLang,
        displayName,
        provider,
        modelType,
        totalSizeBytes,
        encoderUrl,
        decoderUrl,
        tokenizerUrl,
        description,
        isInstalled,
        localPath,
      ];
}
