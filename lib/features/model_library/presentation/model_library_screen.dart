import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/whisper_model_info.dart';
import '../../../native/whisper/whisper_model_manager.dart';
import '../../providers.dart';

class ModelLibraryScreen extends ConsumerStatefulWidget {
  const ModelLibraryScreen({super.key});

  @override
  ConsumerState<ModelLibraryScreen> createState() => _ModelLibraryScreenState();
}

class _ModelLibraryScreenState extends ConsumerState<ModelLibraryScreen> {
  final Map<String, double> _downloadProgress = {};
  final Map<String, String> _downloadStatus = {};

  Future<void> _startDownload(WhisperModelInfo model) async {
    setState(() {
      _downloadProgress[model.id] = 0.01;
      _downloadStatus[model.id] = 'Starting download...';
    });

    try {
      await WhisperModelManager().downloadModel(
        model: model,
        onProgress: (p, s) {
          setState(() {
            _downloadProgress[model.id] = p;
            _downloadStatus[model.id] = s;
          });
        },
      );

      ref.invalidate(whisperModelsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.displayName} installed successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadProgress.remove(model.id);
          _downloadStatus.remove(model.id);
        });
      }
    }
  }

  Future<void> _deleteModel(WhisperModelInfo model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Model?'),
        content: Text('This will delete ${model.displayName} from local device storage (${model.formattedSize}).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await WhisperModelManager().deleteModel(model.id);
      ref.invalidate(whisperModelsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelsAsync = ref.watch(whisperModelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Whisper Speech Models'),
      ),
      body: modelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (models) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: models.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final model = models[index];
              final isDownloading = _downloadProgress.containsKey(model.id);
              final progress = _downloadProgress[model.id] ?? 0.0;
              final statusText = _downloadStatus[model.id] ?? '';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            model.isInstalled ? Icons.check_circle : Icons.smart_toy_outlined,
                            color: model.isInstalled ? Colors.green : theme.colorScheme.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  model.displayName,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${model.formattedSize} • ${model.ramRequirement}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          if (model.isInstalled)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              tooltip: 'Delete Model',
                              onPressed: () => _deleteModel(model),
                            )
                          else if (!isDownloading)
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('Download'),
                              onPressed: () => _startDownload(model),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        model.description,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (isDownloading) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 6),
                        Text(
                          statusText,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
