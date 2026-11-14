import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../data/database/app_database.dart';
import '../../../data/serializers/ass_serializer.dart';
import '../../../data/serializers/srt_serializer.dart';
import '../../../data/serializers/vtt_serializer.dart';
import '../../../domain/entities/processing_job.dart';
import '../../../domain/entities/project.dart';
import '../../../domain/entities/subtitle_cue.dart';
import '../../../native/media/media_inspector.dart';
import '../../providers.dart';

class NewProjectScreen extends ConsumerStatefulWidget {
  const NewProjectScreen({super.key});

  @override
  ConsumerState<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends ConsumerState<NewProjectScreen> {
  final TextEditingController _nameController = TextEditingController();
  String? _selectedMediaPath;
  String? _selectedSubtitlePath;
  MediaMetadata? _mediaMetadata;

  String _sourceLanguage = 'auto';
  String? _targetLanguage;
  String _selectedModel = 'base';
  bool _isLoading = false;

  final List<Map<String, String>> _languages = [
    {'code': 'auto', 'name': 'Auto-detect Spoken Language'},
    {'code': 'en', 'name': 'English'},
    {'code': 'ja', 'name': 'Japanese'},
    {'code': 'ko', 'name': 'Korean'},
    {'code': 'hi', 'name': 'Hindi'},
    {'code': 'ta', 'name': 'Tamil'},
    {'code': 'es', 'name': 'Spanish'},
    {'code': 'fr', 'name': 'French'},
    {'code': 'de', 'name': 'German'},
    {'code': 'zh', 'name': 'Chinese'},
  ];

  Future<void> _pickMediaFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mkv', 'mov', 'avi', 'webm', 'mp3', 'wav', 'm4a', 'aac', 'flac'],
    );

    if (files.isNotEmpty && files.first.path != null) {
      final path = files.first.path!;
      final meta = await MediaInspector().inspectMedia(path);
      setState(() {
        _selectedMediaPath = path;
        _selectedSubtitlePath = null;
        _mediaMetadata = meta;
        if (_nameController.text.isEmpty) {
          _nameController.text = p.basenameWithoutExtension(path);
        }
      });
    }
  }

  Future<void> _pickSubtitleFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass'],
    );

    if (files.isNotEmpty && files.first.path != null) {
      final path = files.first.path!;
      setState(() {
        _selectedSubtitlePath = path;
        if (_nameController.text.isEmpty) {
          _nameController.text = p.basenameWithoutExtension(path);
        }
      });
    }
  }

  Future<void> _createProject() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a project name')),
      );
      return;
    }

    if (_selectedMediaPath == null && _selectedSubtitlePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a media file or subtitle file')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final projectId = const Uuid().v4();
      final now = DateTime.now();

      // Case 1: Importing existing subtitle directly without AI inference
      if (_selectedSubtitlePath != null) {
        final subFile = File(_selectedSubtitlePath!);
        final content = await subFile.readAsString();
        final ext = p.extension(_selectedSubtitlePath!).toLowerCase();

        List<SubtitleCue> cues = [];
        if (ext == '.vtt') {
          cues = VttSerializer.parse(content, projectId: projectId);
        } else if (ext == '.ass') {
          cues = AssSerializer.parse(content, projectId: projectId);
        } else {
          cues = SrtSerializer.parse(content, projectId: projectId);
        }

        final project = Project(
          id: projectId,
          name: _nameController.text.trim(),
          createdAt: now,
          updatedAt: now,
          mediaPath: _selectedMediaPath,
          subtitleFilePath: _selectedSubtitlePath,
          sourceLanguage: _sourceLanguage,
          targetLanguage: _targetLanguage,
          cueCount: cues.length,
          durationMs: _mediaMetadata?.durationMs,
          status: ProjectStatus.ready,
        );

        await ref.read(projectsProvider.notifier).addOrUpdateProject(project);
        await AppDatabase().replaceCuesForProject(projectId, cues);

        if (mounted) {
          context.go('/editor/$projectId');
        }
        return;
      }

      // Case 2: New AI transcription job
      final project = Project(
        id: projectId,
        name: _nameController.text.trim(),
        createdAt: now,
        updatedAt: now,
        mediaPath: _selectedMediaPath,
        sourceLanguage: _sourceLanguage,
        targetLanguage: _targetLanguage,
        cueCount: 0,
        durationMs: _mediaMetadata?.durationMs,
        status: ProjectStatus.transcribing,
      );

      await ref.read(projectsProvider.notifier).addOrUpdateProject(project);

      final job = ProcessingJob(
        id: const Uuid().v4(),
        projectId: projectId,
        title: _nameController.text.trim(),
        stage: JobStage.queued,
        createdAt: now,
        inputPath: _selectedMediaPath,
      );

      await ref.read(jobsProvider.notifier).addJob(job);

      if (mounted) {
        context.go('/batch-queue');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating project: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelsAsync = ref.watch(whisperModelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Subtitle Project'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Project Name',
                hintText: 'e.g. My Movie Subtitles',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Select Media Source',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: _selectedMediaPath != null ? theme.colorScheme.primaryContainer.withAlpha(50) : null,
                    ),
                    icon: const Icon(Icons.video_file_outlined),
                    label: Text(_selectedMediaPath != null ? 'Change Video/Audio' : 'Select Movie/Audio'),
                    onPressed: _pickMediaFile,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: _selectedSubtitlePath != null ? theme.colorScheme.secondaryContainer.withAlpha(50) : null,
                    ),
                    icon: const Icon(Icons.subtitles_outlined),
                    label: Text(_selectedSubtitlePath != null ? 'Change Subtitle' : 'Import SRT/VTT/ASS'),
                    onPressed: _pickSubtitleFile,
                  ),
                ),
              ],
            ),
            if (_selectedMediaPath != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.basename(_selectedMediaPath!), style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (_mediaMetadata != null)
                              Text('Size: ${_mediaMetadata!.formattedFileSize}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_selectedSubtitlePath != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.blueAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Subtitle: ${p.basename(_selectedSubtitlePath!)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Language Configuration',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _sourceLanguage,
              decoration: const InputDecoration(
                labelText: 'Source Audio Language',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.language_rounded),
              ),
              items: _languages.map((l) {
                return DropdownMenuItem(
                  value: l['code'],
                  child: Text(l['name']!),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _sourceLanguage = val);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              value: _targetLanguage,
              decoration: const InputDecoration(
                labelText: 'Target Neural Translation Language (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.translate_rounded),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('None (Keep original transcript)')),
                ..._languages.where((l) => l['code'] != 'auto').map((l) {
                  return DropdownMenuItem(
                    value: l['code'],
                    child: Text('Translate to ${l['name']}'),
                  );
                }),
              ],
              onChanged: (val) => setState(() => _targetLanguage = val),
            ),
            if (_selectedSubtitlePath == null) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Whisper Speech Model',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Manage Models'),
                    onPressed: () => context.push('/models'),
                  ),
                ],
              ),
              modelsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
                data: (models) {
                  return Column(
                    children: models.map((m) {
                      return RadioListTile<String>(
                        value: m.id,
                        groupValue: _selectedModel,
                        title: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${m.formattedSize} • ${m.ramRequirement} • ${m.isInstalled ? "Installed" : "Will download"}'),
                        secondary: Icon(
                          m.isInstalled ? Icons.check_circle : Icons.cloud_download_outlined,
                          color: m.isInstalled ? Colors.green : null,
                        ),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedModel = val);
                        },
                      );
                    }).toList(),
                  );
                },
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  _selectedSubtitlePath != null ? 'Open Subtitle Editor' : 'Start Processing',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _isLoading ? null : _createProject,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
