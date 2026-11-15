import 'package:equatable/equatable.dart';

enum JobStage {
  queued,
  preparing,
  extractingAudio,
  running,
  transcribing,
  translating,
  formatting,
  paused,
  recoverable,
  completed,
  failed,
  cancelled;

  String get displayName {
    switch (this) {
      case JobStage.queued:
        return 'Queued';
      case JobStage.preparing:
        return 'Preparing';
      case JobStage.extractingAudio:
        return 'Extracting Audio';
      case JobStage.running:
        return 'Running';
      case JobStage.transcribing:
        return 'Transcribing (Whisper)';
      case JobStage.translating:
        return 'Translating';
      case JobStage.formatting:
        return 'Formatting Subtitles';
      case JobStage.paused:
        return 'Paused';
      case JobStage.recoverable:
        return 'Recoverable (Interrupted)';
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
      this == JobStage.preparing ||
      this == JobStage.extractingAudio ||
      this == JobStage.running ||
      this == JobStage.transcribing ||
      this == JobStage.translating ||
      this == JobStage.formatting;

  bool get isRecoverable => this == JobStage.recoverable;
  bool get isPaused => this == JobStage.paused;
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
  final String selectedModel;
  final int? elapsedSeconds;
  final int? etaSeconds;
  final int? audioDurationSeconds;
  final int? currentChunk;
  final int? totalChunks;

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
    this.selectedModel = 'base',
    this.elapsedSeconds,
    this.etaSeconds,
    this.audioDurationSeconds,
    this.currentChunk,
    this.totalChunks,
  });

  String? get formattedElapsed {
    if (elapsedSeconds == null) return null;
    final d = Duration(seconds: elapsedSeconds!);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  String? get formattedEta {
    if (etaSeconds == null) return null;
    final d = Duration(seconds: etaSeconds!);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  String? get formattedEstimatedTotal {
    if (elapsedSeconds == null || etaSeconds == null) return null;
    final d = Duration(seconds: elapsedSeconds! + etaSeconds!);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  String? get formattedAudioDuration {
    if (audioDurationSeconds == null) return null;
    final d = Duration(seconds: audioDurationSeconds!);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

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
    String? selectedModel,
    int? elapsedSeconds,
    int? etaSeconds,
    int? audioDurationSeconds,
    int? currentChunk,
    int? totalChunks,
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
      selectedModel: selectedModel ?? this.selectedModel,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      audioDurationSeconds: audioDurationSeconds ?? this.audioDurationSeconds,
      currentChunk: currentChunk ?? this.currentChunk,
      totalChunks: totalChunks ?? this.totalChunks,
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
      'selected_model': selectedModel,
      'elapsed_seconds': elapsedSeconds,
      'eta_seconds': etaSeconds,
      'audio_duration_seconds': audioDurationSeconds,
      'current_chunk': currentChunk,
      'total_chunks': totalChunks,
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
      selectedModel: map['selected_model'] as String? ?? 'base',
      elapsedSeconds: map['elapsed_seconds'] as int?,
      etaSeconds: map['eta_seconds'] as int?,
      audioDurationSeconds: map['audio_duration_seconds'] as int?,
      currentChunk: map['current_chunk'] as int?,
      totalChunks: map['total_chunks'] as int?,
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
        selectedModel,
        elapsedSeconds,
        etaSeconds,
        audioDurationSeconds,
        currentChunk,
        totalChunks,
      ];
}
