import 'package:equatable/equatable.dart';

class WhisperModelInfo extends Equatable {
  final String id;
  final String displayName;
  final String fileName;
  final String downloadUrl;
  final int sizeBytes;
  final String ramRequirement;
  final String description;
  final String? sha256;
  final bool isInstalled;
  final String? localPath;

  const WhisperModelInfo({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.ramRequirement,
    required this.description,
    this.sha256,
    this.isInstalled = false,
    this.localPath,
  });

  String get formattedSize {
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1000) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }

  WhisperModelInfo copyWith({
    String? id,
    String? displayName,
    String? fileName,
    String? downloadUrl,
    int? sizeBytes,
    String? ramRequirement,
    String? description,
    String? sha256,
    bool? isInstalled,
    String? localPath,
  }) {
    return WhisperModelInfo(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      fileName: fileName ?? this.fileName,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      ramRequirement: ramRequirement ?? this.ramRequirement,
      description: description ?? this.description,
      sha256: sha256 ?? this.sha256,
      isInstalled: isInstalled ?? this.isInstalled,
      localPath: localPath ?? this.localPath,
    );
  }

  static const List<WhisperModelInfo> catalog = [
    WhisperModelInfo(
      id: 'tiny',
      displayName: 'Whisper Tiny (Multilingual)',
      fileName: 'ggml-tiny.bin',
      downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin',
      sizeBytes: 77793674, // ~75 MB
      ramRequirement: '~390 MB RAM',
      description: 'Ultra-fast speech recognition with minimal memory footprint. Ideal for fast drafts and low-spec devices.',
      sha256: 'bd577a11320e3526d36123314343a87340ec548fa88d745f6ed977457ec682a0',
    ),
    WhisperModelInfo(
      id: 'base',
      displayName: 'Whisper Base (Multilingual)',
      fileName: 'ggml-base.bin',
      downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
      sizeBytes: 147964211, // ~142 MB
      ramRequirement: '~500 MB RAM',
      description: 'Recommended default model. Excellent balance of speed and high speech accuracy across 99+ languages.',
      sha256: '46514b776037a41ab25d742df84e7fa340ff6e67a3f500e8480c6713b574a00c',
    ),
    WhisperModelInfo(
      id: 'small',
      displayName: 'Whisper Small (Multilingual)',
      fileName: 'ggml-small.bin',
      downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
      sizeBytes: 487848619, // ~466 MB
      ramRequirement: '~1.0 GB RAM',
      description: 'High accuracy model for complex accents, noisy backgrounds, and multi-speaker dialogues.',
      sha256: '55356645c2b361a969dfd0ef2c5a50d530abb43a31798147458e170a4a377969',
    ),
    WhisperModelInfo(
      id: 'medium',
      displayName: 'Whisper Medium (Multilingual)',
      fileName: 'ggml-medium.bin',
      downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin',
      sizeBytes: 1533753177, // ~1.5 GB
      ramRequirement: '~2.6 GB RAM',
      description: 'Near-human transcription accuracy. Best suited for high-end phones and desktop workstations.',
      sha256: 'fd9727b6e1217c2f614f9b698455c477767d4f9b5c3ff61a92e105e468be5484',
    ),
  ];

  @override
  List<Object?> get props => [
        id,
        displayName,
        fileName,
        downloadUrl,
        sizeBytes,
        ramRequirement,
        description,
        sha256,
        isInstalled,
        localPath,
      ];
}
