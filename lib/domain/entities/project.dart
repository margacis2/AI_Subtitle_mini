import 'package:equatable/equatable.dart';

enum ProjectStatus {
  created,
  extractingAudio,
  transcribing,
  translating,
  ready,
  error;

  String get displayName {
    switch (this) {
      case ProjectStatus.created:
        return 'Created';
      case ProjectStatus.extractingAudio:
        return 'Extracting Audio';
      case ProjectStatus.transcribing:
        return 'Transcribing';
      case ProjectStatus.translating:
        return 'Translating';
      case ProjectStatus.ready:
        return 'Ready';
      case ProjectStatus.error:
        return 'Error';
    }
  }
}

class Project extends Equatable {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? mediaPath;
  final String? audioPath;
  final String? subtitleFilePath;
  final String sourceLanguage;
  final String? targetLanguage;
  final int cueCount;
  final int? durationMs;
  final ProjectStatus status;

  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.mediaPath,
    this.audioPath,
    this.subtitleFilePath,
    this.sourceLanguage = 'auto',
    this.targetLanguage,
    this.cueCount = 0,
    this.durationMs,
    this.status = ProjectStatus.ready,
  });

  Project copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? mediaPath,
    String? audioPath,
    String? subtitleFilePath,
    String? sourceLanguage,
    String? targetLanguage,
    int? cueCount,
    int? durationMs,
    ProjectStatus? status,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mediaPath: mediaPath ?? this.mediaPath,
      audioPath: audioPath ?? this.audioPath,
      subtitleFilePath: subtitleFilePath ?? this.subtitleFilePath,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      cueCount: cueCount ?? this.cueCount,
      durationMs: durationMs ?? this.durationMs,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'media_path': mediaPath,
      'audio_path': audioPath,
      'subtitle_file_path': subtitleFilePath,
      'source_language': sourceLanguage,
      'target_language': targetLanguage,
      'cue_count': cueCount,
      'duration_ms': durationMs,
      'status': status.name,
    };
  }

  factory Project.fromMap(Map<String, dynamic> map) {
    ProjectStatus parseStatus(String? s) {
      return ProjectStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => ProjectStatus.ready,
      );
    }

    return Project(
      id: map['id'] as String,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      mediaPath: map['media_path'] as String?,
      audioPath: map['audio_path'] as String?,
      subtitleFilePath: map['subtitle_file_path'] as String?,
      sourceLanguage: map['source_language'] as String? ?? 'auto',
      targetLanguage: map['target_language'] as String?,
      cueCount: map['cue_count'] as int? ?? 0,
      durationMs: map['duration_ms'] as int?,
      status: parseStatus(map['status'] as String?),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        createdAt,
        updatedAt,
        mediaPath,
        audioPath,
        subtitleFilePath,
        sourceLanguage,
        targetLanguage,
        cueCount,
        durationMs,
        status,
      ];
}
