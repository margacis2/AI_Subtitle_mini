import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/platform/device_info_service.dart';
import '../data/database/app_database.dart';
import '../domain/entities/processing_job.dart';
import '../domain/entities/project.dart';
import '../domain/entities/subtitle_cue.dart';
import '../domain/entities/translation_pack_info.dart';
import '../domain/entities/user_settings.dart';
import '../domain/entities/whisper_model_info.dart';
import '../domain/services/job_scheduler.dart';
import '../domain/services/translation_pack_manager.dart';
import '../native/whisper/whisper_model_manager.dart';

// --- USER SETTINGS NOTIFIER ---
class UserSettingsNotifier extends Notifier<UserSettings> {
  static const String _key = 'user_settings';

  @override
  UserSettings build() {
    _loadSettings();
    return const UserSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_key);
      if (str != null) {
        state = UserSettings.fromMap(jsonDecode(str));
      }
    } catch (_) {}
  }

  Future<void> updateSettings(UserSettings settings) async {
    state = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(settings.toMap()));
    } catch (_) {}
  }

  void setThemeMode(ThemeMode mode) {
    updateSettings(state.copyWith(themeMode: mode));
  }

  void setCensorMaskType(CensorMaskType type) {
    updateSettings(state.copyWith(censorMaskType: type));
  }

  void setExportFormat(String format) {
    updateSettings(state.copyWith(defaultExportFormat: format));
  }

  void setModelId(String id) {
    updateSettings(state.copyWith(selectedModelId: id));
  }

  void setThreadCount(int count) {
    updateSettings(state.copyWith(threadCount: count));
  }
}

final settingsProvider = NotifierProvider<UserSettingsNotifier, UserSettings>(
  UserSettingsNotifier.new,
);

// --- PROJECTS NOTIFIER ---
class ProjectsNotifier extends AsyncNotifier<List<Project>> {
  final AppDatabase _db = AppDatabase();

  @override
  FutureOr<List<Project>> build() async {
    return await _db.getAllProjects();
  }

  Future<void> loadProjects() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _db.getAllProjects());
  }

  Future<void> addOrUpdateProject(Project project) async {
    await _db.saveProject(project);
    await loadProjects();
  }

  Future<void> deleteProject(String id) async {
    await _db.deleteProject(id);
    await loadProjects();
  }
}

final projectsProvider = AsyncNotifierProvider<ProjectsNotifier, List<Project>>(
  ProjectsNotifier.new,
);

// --- JOBS NOTIFIER ---
class JobsNotifier extends AsyncNotifier<List<ProcessingJob>> {
  final AppDatabase _db = AppDatabase();

  @override
  FutureOr<List<ProcessingJob>> build() async {
    return await _db.getAllJobs();
  }

  Future<void> loadJobs() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _db.getAllJobs());
  }

  Future<void> addJob(ProcessingJob job) async {
    await _db.saveJob(job);
    await loadJobs();
    JobScheduler().triggerQueueProcessing();
  }

  Future<void> deleteJob(String id) async {
    await _db.deleteJob(id);
    await loadJobs();
  }

  Future<void> retryJob(String id) async {
    await JobScheduler().retryJob(id);
    await loadJobs();
  }

  Future<void> cancelJob(String id) async {
    await JobScheduler().cancelJob(id);
    await loadJobs();
  }

  Future<void> clearCompleted() async {
    await _db.clearCompletedJobs();
    await loadJobs();
  }
}

final jobsProvider = AsyncNotifierProvider<JobsNotifier, List<ProcessingJob>>(
  JobsNotifier.new,
);

// --- CURRENT PROJECT CUES PROVIDER ---
final projectCuesProvider = FutureProvider.family<List<SubtitleCue>, String>((ref, projectId) async {
  final db = AppDatabase();
  return await db.getCuesForProject(projectId);
});

// --- WHISPER MODELS PROVIDER ---
final whisperModelsProvider = FutureProvider<List<WhisperModelInfo>>((ref) async {
  return await WhisperModelManager().getModelsWithStatus();
});

// --- LANGUAGE PACKS PROVIDER ---
final languagePacksProvider = FutureProvider<List<TranslationPackInfo>>((ref) async {
  return await TranslationPackManager().getPacksWithStatus();
});

// --- DIAGNOSTICS PROVIDER ---
final diagnosticsProvider = FutureProvider<DeviceDiagnostics>((ref) async {
  return await DeviceInfoService().getDiagnostics();
});
