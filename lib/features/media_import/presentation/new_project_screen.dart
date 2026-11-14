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
    {'code': 'auto', 'name': 'Auto-detect Language'},
    {'code': 'en', 'name': 'English'},
    {'code': 'es', 'name': 'Spanish'},
    {'code': 'fr', 'name': 'French'},
    {'code': 'de', 'name': 'German'},
    {'code': 'ja', 'name': 'Japanese'},
    {'code': 'ko', 'name': 'Korean'},
    {'code': 'hi', 'name': 'Hindi'},
    {'code': 'ta', 'name': 'Tamil'},
    {'code': 'zh', 'name': 'Chinese'},
  ];

  Future<void> _pickMediaFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mkv', 'mov', 'avi', 'webm', 'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'],
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file picker: $e')),
        );
      }
    }
  }

  Future<void> _pickSubtitleFile() async {
    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open subtitle file: $e')),
        );
      }
    }
  }

  Future<void> _createProject() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a project name')),
      );
      return;
    }

    if (_selectedMediaPath == null && _selectedSubtitlePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a video, audio, or subtitle file')),
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
          name: name,
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

      // Case 2: New AI transcription & neural translation pipeline
      final project = Project(
        id: projectId,
        name: name,
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
        title: name,
        stage: JobStage.queued,
        createdAt: now,
        inputPath: _selectedMediaPath,
        currentStep: 'Queued for processing...',
      );

      await ref.read(jobsProvider.notifier).addJob(job);

      if (mounted) {
        // Navigate directly to live queue to watch transcription progress in real-time
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project Name Field
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Project Name',
                hintText: 'e.g. My Movie Subtitle',
                prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
              ),
            ),
            const SizedBox(height: 24),

            // Media Selection Cards
            Text(
              'Select Media Source',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _pickMediaFile,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _selectedMediaPath != null
                            ? theme.colorScheme.primaryContainer.withAlpha(50)
                            : theme.cardTheme.color,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _selectedMediaPath != null
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                          width: _selectedMediaPath != null ? 2 : 1.2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.video_library_rounded,
                            size: 32,
                            color: _selectedMediaPath != null
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _selectedMediaPath != null ? 'Change Media' : 'Pick Video / Audio',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'MP4, MKV, MP3, WAV',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _pickSubtitleFile,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _selectedSubtitlePath != null
                            ? theme.colorScheme.secondaryContainer.withAlpha(50)
                            : theme.cardTheme.color,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _selectedSubtitlePath != null
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.outline,
                          width: _selectedSubtitlePath != null ? 2 : 1.2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.subtitles_rounded,
                            size: 32,
                            color: _selectedSubtitlePath != null
                                ? theme.colorScheme.secondary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _selectedSubtitlePath != null ? 'Change Subtitle' : 'Import Subtitle',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'SRT, VTT, ASS',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_selectedMediaPath != null) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.basename(_selectedMediaPath!),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_mediaMetadata != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${_mediaMetadata!.formattedFileSize} • Duration: ${_mediaMetadata!.formattedDuration}',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() {
                          _selectedMediaPath = null;
                          _mediaMetadata = null;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_selectedSubtitlePath != null) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.subtitles_rounded, color: Color(0xFF6366F1), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          p.basename(_selectedSubtitlePath!),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _selectedSubtitlePath = null),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Language Configuration
            Text(
              'Language & Translation Pipeline',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _sourceLanguage,
              decoration: const InputDecoration(
                labelText: 'Spoken Audio Language',
                prefixIcon: Icon(Icons.mic_none_rounded),
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
              initialValue: _targetLanguage,
              decoration: const InputDecoration(
                labelText: 'Target Neural Translation (Optional)',
                prefixIcon: Icon(Icons.translate_rounded),
                helperText: 'Translates subtitles to target language while preserving timestamps',
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
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Speech Recognition Model',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Model Library'),
                    onPressed: () => context.push('/models'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              modelsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const SizedBox.shrink(),
                data: (models) {
                  return Column(
                    children: models.map((m) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: RadioListTile<String>(
                          value: m.id,
                          groupValue: _selectedModel,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: _selectedModel == m.id
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                              width: _selectedModel == m.id ? 1.8 : 1,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: m.isInstalled
                                      ? const Color(0xFF10B981).withAlpha(40)
                                      : theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  m.isInstalled ? 'Ready' : m.formattedSize,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: m.isInstalled ? const Color(0xFF10B981) : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text('RAM: ${m.ramRequirement} • Offline inference'),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedModel = val);
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],

            const SizedBox(height: 36),

            // Start Conversion Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.bolt_rounded, size: 22),
                label: Text(
                  _selectedSubtitlePath != null ? 'Open Subtitle Editor' : 'Start Conversion',
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
