import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/translation_pack_info.dart';
import '../../../domain/services/translation_pack_manager.dart';
import '../../providers.dart';

class LanguagePacksScreen extends ConsumerStatefulWidget {
  const LanguagePacksScreen({super.key});

  @override
  ConsumerState<LanguagePacksScreen> createState() => _LanguagePacksScreenState();
}

class _LanguagePacksScreenState extends ConsumerState<LanguagePacksScreen> {
  final Map<String, double> _downloadProgress = {};
  final Map<String, String> _downloadStatus = {};
  final Map<String, CancelToken> _cancelTokens = {};

  void _cancelDownload(String packId) {
    _cancelTokens[packId]?.cancel('Cancelled by user');
    _cancelTokens.remove(packId);
    setState(() {
      _downloadProgress.remove(packId);
      _downloadStatus.remove(packId);
    });
  }

  Future<void> _startDownload(TranslationPackInfo pack) async {
    final cancelToken = CancelToken();
    _cancelTokens[pack.id] = cancelToken;

    setState(() {
      _downloadProgress[pack.id] = 0.05;
      _downloadStatus[pack.id] = 'Preparing download...';
    });

    try {
      await TranslationPackManager().downloadPack(
        pack: pack,
        cancelToken: cancelToken,
        onProgress: (p, s) {
          if (!mounted) return;
          setState(() {
            _downloadProgress[pack.id] = p;
            _downloadStatus[pack.id] = s;
          });
        },
      );

      ref.invalidate(languagePacksProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${pack.displayName} pack installed successfully.')),
        );
      }
    } catch (e) {
      if (mounted && !cancelToken.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Installation failed: $e')),
        );
      }
    } finally {
      _cancelTokens.remove(pack.id);
      if (mounted) {
        setState(() {
          _downloadProgress.remove(pack.id);
          _downloadStatus.remove(pack.id);
        });
      }
    }
  }

  Future<void> _deletePack(TranslationPackInfo pack) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Uninstall Language Pack?'),
        content: Text('This will delete ${pack.displayName} neural model from local storage (${pack.formattedSize}).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TranslationPackManager().uninstallPack(pack.id);
      ref.invalidate(languagePacksProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packsAsync = ref.watch(languagePacksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Neural Language Packs'),
      ),
      body: packsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (packs) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: packs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final pack = packs[index];
              final isDownloading = _downloadProgress.containsKey(pack.id);
              final progress = _downloadProgress[pack.id] ?? 0.0;
              final statusText = _downloadStatus[pack.id] ?? '';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            pack.isInstalled ? Icons.check_circle : Icons.translate_rounded,
                            color: pack.isInstalled ? Colors.green : theme.colorScheme.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pack.displayName,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${pack.formattedSize} • ${pack.modelType}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          if (pack.isInstalled)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              tooltip: 'Uninstall Pack',
                              onPressed: () => _deletePack(pack),
                            )
                          else if (!isDownloading)
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('Install'),
                              onPressed: () => _startDownload(pack),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        pack.description,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Provider: ${pack.provider}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant.withAlpha(150)),
                      ),
                      if (isDownloading) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                statusText,
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _cancelDownload(pack.id),
                              icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.redAccent),
                              label: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                            ),
                          ],
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
