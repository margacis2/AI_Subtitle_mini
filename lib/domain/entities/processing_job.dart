import 'package:equatable/equatable.dart';

enum JobStage {
  queued,
  extractingAudio,
  transcribing,
  translating,
  formatting,
  completed,
  failed,
  cancelled;

  String get displayName {
    switch (this) {
      case JobStage.queued:
        return 'Queued';
      case JobStage.extractingAudio:
        return 'Extracting Audio';
      case JobStage.transcribing:
        return 'Transcribing (Whisper)';
      case JobStage.translating:
        return 'Translating';
      case JobStage.formatting:
        return 'Formatting Subtitles';
      case JobStage.completed:
        return 'Completed';
      case JobStage.failed:
        return 'Failed';
      case JobStage.cancelled:
        return 'Cancelled';
    }
  }

  bool get isActive =>
      this == JobStage.queued ||
      this == JobStage.extractingAudio ||
      this == JobStage.transcribing ||
      this == JobStage.translating ||
      this == JobStage.formatting;
}

class ProcessingJob extends Equatable {
  final String id;
  final String projectId;
  final String title;
  final JobStage stage;
  final double progress;
  final String? currentStep;
  final String? errorDetails;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int retryCount;
  final String? inputPath;
  final String? outputPath;
  final String? settings;

  const ProcessingJob({
    required this.id,
    required this.projectId,
    required this.title,
    required this.stage,
    this.progress = 0.0,
    this.currentStep,
    this.errorDetails,
    required this.createdAt,
    this.completedAt,
    this.retryCount = 0,
    this.inputPath,
    this.outputPath,
    this.settings,
  });

  ProcessingJob copyWith({
    String? id,
    String? projectId,
    String? title,
    JobStage? stage,
    double? progress,
    String? currentStep,
    String? errorDetails,
    DateTime? createdAt,
    DateTime? completedAt,
    int? retryCount,
    String? inputPath,
    String? outputPath,
    String? settings,
  }) {
    return ProcessingJob(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      currentStep: currentStep ?? this.currentStep,
      errorDetails: errorDetails ?? this.errorDetails,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      retryCount: retryCount ?? this.retryCount,
      inputPath: inputPath ?? this.inputPath,
      outputPath: outputPath ?? this.outputPath,
      settings: settings ?? this.settings,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'project_id': projectId,
      'title': title,
      'stage': stage.name,
      'progress': progress,
      'current_step': currentStep,
      'error_details': errorDetails,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'retry_count': retryCount,
      'input_path': inputPath,
      'output_path': outputPath,
      'settings': settings,
    };
  }

  factory ProcessingJob.fromMap(Map<String, dynamic> map) {
    JobStage parseStage(String? s) {
      return JobStage.values.firstWhere(
        (e) => e.name == s,
        orElse: () => JobStage.queued,
      );
    }

    return ProcessingJob(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      title: map['title'] as String,
      stage: parseStage(map['stage'] as String?),
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      currentStep: map['current_step'] as String?,
      errorDetails: map['error_details'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      completedAt: map['completed_at'] != null ? DateTime.parse(map['completed_at'] as String) : null,
      retryCount: map['retry_count'] as int? ?? 0,
      inputPath: map['input_path'] as String?,
      outputPath: map['output_path'] as String?,
      settings: map['settings'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        projectId,
        title,
        stage,
        progress,
        currentStep,
        errorDetails,
        createdAt,
        completedAt,
        retryCount,
        inputPath,
        outputPath,
        settings,
      ];
}
