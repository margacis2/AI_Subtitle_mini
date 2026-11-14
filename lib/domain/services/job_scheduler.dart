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

      // Loop to next
      await _processNextJob(settings);
    } catch (e) {
      _isProcessing = false;
    }
  }

  Future<void> _executeJob(ProcessingJob job, UserSettings settings) async {
    try {
      final project = await _db.getProject(job.projectId);
      if (project == null) {
        await _db.saveJob(job.copyWith(
          stage: JobStage.failed,
          errorDetails: 'Project not found.',
        ));
        return;
      }

      // Step 1: Extract Audio
      await _updateJob(job, JobStage.extractingAudio, 0.1, 'Extracting 16kHz audio track...');
      String audioPath = project.audioPath ?? '';
      if (audioPath.isEmpty || !File(audioPath).existsSync()) {
        if (project.mediaPath != null && File(project.mediaPath!).existsSync()) {
          final extractedFile = await _audioExtractor.extractAudio(
            inputPath: project.mediaPath!,
            onProgress: (p, s) {
              _updateJob(job, JobStage.extractingAudio, 0.1 + (p * 0.2), s);
            },
          );
          audioPath = extractedFile.path;
          await _db.saveProject(project.copyWith(audioPath: audioPath));
        } else {
          throw Exception('No valid media file found to process.');
        }
      }

      // Step 2: Speech Transcription (Whisper)
      await _updateJob(job, JobStage.transcribing, 0.35, 'Initializing speech model...');
      final models = await _modelManager.getModelsWithStatus();
      final installedModel = models.firstWhere(
        (m) => m.isInstalled,
        orElse: () => models.firstWhere((m) => m.id == 'tiny'),
      );

      final modelPath = installedModel.localPath ?? '';

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

      // Step 3: Optional Translation
      List<SubtitleCue> cuesToFormat = rawCues;
      if (project.targetLanguage != null &&
          project.targetLanguage!.isNotEmpty &&
          project.targetLanguage != project.sourceLanguage) {
        await _updateJob(job, JobStage.translating, 0.75, 'Translating subtitles...');
        cuesToFormat = await _translationEngine.translateCues(
          cues: rawCues,
          sourceLang: project.sourceLanguage,
          targetLang: project.targetLanguage!,
          onProgress: (p, s) {
            _updateJob(job, JobStage.translating, 0.75 + (p * 0.15), s);
          },
        );
      }

      // Step 4: Formatting & Masking
      await _updateJob(job, JobStage.formatting, 0.92, 'Formatting subtitle cues and timing...');
      final splitCues = _splittingService.splitCues(cuesToFormat);

      // Apply profanity mask
      final finalCues = ProfanityFilterService.maskCues(
        splitCues,
        settings.censorMaskType,
        placeholder: settings.censorPlaceholder,
      );

      // Save cues into database
      await _db.replaceCuesForProject(project.id, finalCues);

      // Step 5: Mark Completed
      await _db.saveProject(project.copyWith(
        status: ProjectStatus.ready,
        cueCount: finalCues.length,
      ));

      await _db.saveJob(job.copyWith(
        stage: JobStage.completed,
        progress: 1.0,
        currentStep: 'Completed',
        completedAt: DateTime.now(),
      ));
    } catch (e) {
      await _db.saveJob(job.copyWith(
        stage: JobStage.failed,
        errorDetails: e.toString(),
      ));
    }
  }

  Future<void> _updateJob(ProcessingJob job, JobStage stage, double progress, String step) async {
    final updated = job.copyWith(
      stage: stage,
      progress: progress,
      currentStep: step,
    );
    await _db.saveJob(updated);
  }

  Future<void> cancelJob(String jobId) async {
    final job = await _db.getJob(jobId);
    if (job != null) {
      await _db.saveJob(job.copyWith(
        stage: JobStage.cancelled,
        currentStep: 'Job cancelled by user',
      ));
    }
  }

  Future<void> retryJob(String jobId) async {
    final job = await _db.getJob(jobId);
    if (job != null) {
      await _db.saveJob(job.copyWith(
        stage: JobStage.queued,
        progress: 0.0,
        currentStep: 'Queued for retry',
        retryCount: job.retryCount + 1,
        errorDetails: null,
      ));
      triggerQueueProcessing();
    }
  }
}
