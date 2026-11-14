import 'dart:async';
import 'dart:io';
import '../../data/database/app_database.dart';
import '../../native/media/audio_extractor.dart';
import '../../native/whisper/whisper_engine.dart';
import '../../native/whisper/whisper_model_manager.dart';
import '../entities/processing_job.dart';
import '../entities/project.dart';
import '../entities/subtitle_cue.dart';
import '../entities/user_settings.dart';
import 'offline_translation_engine.dart';
import 'profanity_filter_service.dart';
import 'subtitle_splitting_service.dart';

class JobScheduler {
  static final JobScheduler _instance = JobScheduler._internal();
  factory JobScheduler() => _instance;
  JobScheduler._internal();

  final AppDatabase _db = AppDatabase();
  final AudioExtractor _audioExtractor = AudioExtractor();
  final WhisperEngine _whisperEngine = WhisperEngine();
  final WhisperModelManager _modelManager = WhisperModelManager();
  final OfflineTranslationEngine _translationEngine = OfflineTranslationEngine();
  final SubtitleSplittingService _splittingService = const SubtitleSplittingService();

  final StreamController<ProcessingJob> _jobStreamController = StreamController<ProcessingJob>.broadcast();
  Stream<ProcessingJob> get jobStream => _jobStreamController.stream;

  bool _isProcessing = false;

  void triggerQueueProcessing({UserSettings? settings}) {
    if (_isProcessing) return;
    _processNextJob(settings ?? const UserSettings());
  }

  Future<void> _processNextJob(UserSettings settings) async {
    _isProcessing = true;
    try {
      final allJobs = await _db.getAllJobs();
      final queued = allJobs.where((j) => j.stage == JobStage.queued).toList();

      if (queued.isEmpty) {
        _isProcessing = false;
        return;
      }

      final job = queued.first;
      await _executeJob(job, settings);

      // Loop to process next queued job
      await _processNextJob(settings);
    } catch (e) {
      _isProcessing = false;
    }
  }

  Future<void> _executeJob(ProcessingJob job, UserSettings settings) async {
    try {
      final project = await _db.getProject(job.projectId);
      if (project == null) {
        final failed = job.copyWith(
          stage: JobStage.failed,
          errorDetails: 'Project metadata not found.',
        );
        await _db.saveJob(failed);
        _jobStreamController.add(failed);
        return;
      }

      // Step 1: Extract Audio track (16kHz 16-bit mono WAV)
      await _updateJob(job, JobStage.extractingAudio, 0.15, 'Extracting 16kHz audio track from media...');
      String audioPath = project.audioPath ?? '';
      if (audioPath.isEmpty || !File(audioPath).existsSync()) {
        if (project.mediaPath != null && File(project.mediaPath!).existsSync()) {
          final extractedFile = await _audioExtractor.extractAudio(
            inputPath: project.mediaPath!,
            knownDurationMs: project.durationMs,
            onProgress: (p, s) {
              _updateJob(job, JobStage.extractingAudio, 0.15 + (p * 0.15), s);
            },
          );
          audioPath = extractedFile.path;
          await _db.saveProject(project.copyWith(audioPath: audioPath));
        } else {
          throw Exception('Media file could not be accessed.');
        }
      }

      // Step 2: Speech-to-Text Transcription
      await _updateJob(job, JobStage.transcribing, 0.35, 'Initializing speech transcription engine...');
      final models = await _modelManager.getModelsWithStatus();
      final installedList = models.where((m) => m.isInstalled).toList();
      final modelPath = installedList.isNotEmpty ? (installedList.first.localPath ?? '') : '';

      final rawCues = await _whisperEngine.transcribe(
        audioPath: audioPath,
        modelPath: modelPath,
        projectId: project.id,
        language: project.sourceLanguage,
        threadCount: settings.threadCount,
        onProgress: (p, s) {
          _updateJob(job, JobStage.transcribing, 0.35 + (p * 0.35), s);
        },
      );

      // Step 3: Neural Translation (if user requested translation)
      List<SubtitleCue> cuesToFormat = rawCues;
      if (project.targetLanguage != null &&
          project.targetLanguage!.isNotEmpty &&
          project.targetLanguage != project.sourceLanguage) {
        await _updateJob(job, JobStage.translating, 0.75, 'Translating subtitles to ${project.targetLanguage}...');
        cuesToFormat = await _translationEngine.translateCues(
          cues: rawCues,
          sourceLang: project.sourceLanguage,
          targetLang: project.targetLanguage!,
          onProgress: (p, s) {
            _updateJob(job, JobStage.translating, 0.75 + (p * 0.15), s);
          },
        );
      }

      // Step 4: Formatting, Sentence Boundary Splitting & Profanity Filter
      await _updateJob(job, JobStage.formatting, 0.92, 'Formatting subtitle cues and timing alignment...');
      final splitCues = _splittingService.splitCues(cuesToFormat);

      // Apply profanity mask
      final finalCues = ProfanityFilterService.maskCues(
        splitCues,
        settings.censorMaskType,
        placeholder: settings.censorPlaceholder,
      );

      // Save generated cues into database
      await _db.replaceCuesForProject(project.id, finalCues);

      // Step 5: Mark Project & Job Completed
      await _db.saveProject(project.copyWith(
        status: ProjectStatus.ready,
        cueCount: finalCues.length,
        updatedAt: DateTime.now(),
      ));

      final completedJob = job.copyWith(
        stage: JobStage.completed,
        progress: 1.0,
        currentStep: 'Transcription & formatting completed (${finalCues.length} cues)',
        completedAt: DateTime.now(),
      );
      await _db.saveJob(completedJob);
      _jobStreamController.add(completedJob);
    } catch (e) {
      final failedJob = job.copyWith(
        stage: JobStage.failed,
        errorDetails: e.toString(),
        currentStep: 'Failed: ${e.toString()}',
      );
      await _db.saveJob(failedJob);
      _jobStreamController.add(failedJob);
    }
  }

  Future<void> _updateJob(ProcessingJob job, JobStage stage, double progress, String step) async {
    final updated = job.copyWith(
      stage: stage,
      progress: progress,
      currentStep: step,
    );
    await _db.saveJob(updated);
    _jobStreamController.add(updated);
  }

  Future<void> cancelJob(String jobId) async {
    final job = await _db.getJob(jobId);
    if (job != null) {
      final cancelled = job.copyWith(
        stage: JobStage.cancelled,
        currentStep: 'Job cancelled by user',
      );
      await _db.saveJob(cancelled);
      _jobStreamController.add(cancelled);
    }
  }

  Future<void> retryJob(String jobId) async {
    final job = await _db.getJob(jobId);
    if (job != null) {
      final retried = job.copyWith(
        stage: JobStage.queued,
        progress: 0.0,
        currentStep: 'Queued for processing',
        retryCount: job.retryCount + 1,
        errorDetails: null,
      );
      await _db.saveJob(retried);
      _jobStreamController.add(retried);
      triggerQueueProcessing();
    }
  }
}
