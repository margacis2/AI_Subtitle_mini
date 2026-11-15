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
      sizeBytes: 77691713, // ~74.1 MB
      ramRequirement: '~390 MB RAM',
      description: 'Ultra-fast speech recognition with minimal memory footprint. Ideal for fast drafts and low-spec devices.',
      sha256: 'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
    ),
    WhisperModelInfo(
      id: 'base',
      displayName: 'Whisper Base (Multilingual)',
      fileName: 'ggml-base.bin',
      downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
      sizeBytes: 147951465, // ~141.1 MB
      ramRequirement: '~500 MB RAM',
      description: 'Recommended default model. Excellent balance of speed and high speech accuracy across 99+ languages.',
      sha256: '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
    ),
    WhisperModelInfo(
      id: 'small',
      displayName: 'Whisper Small (Multilingual)',
      fileName: 'ggml-small.bin',
      downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
      sizeBytes: 487601967, // ~465.0 MB
      ramRequirement: '~1.0 GB RAM',
      description: 'High accuracy model for complex accents, noisy backgrounds, and multi-speaker dialogues.',
      sha256: '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
    ),
    WhisperModelInfo(
      id: 'medium',
      displayName: 'Whisper Medium (Multilingual)',
      fileName: 'ggml-medium.bin',
      downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin',
      sizeBytes: 1533763059, // ~1462.7 MB
      ramRequirement: '~2.6 GB RAM',
      description: 'Near-human transcription accuracy. Best suited for high-end phones and desktop workstations.',
      sha256: '6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208',
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
