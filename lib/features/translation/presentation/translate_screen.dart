import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/utilities/timestamp_utils.dart';
import '../../../data/serializers/ass_serializer.dart';
import '../../../data/serializers/srt_serializer.dart';
import '../../../data/serializers/txt_serializer.dart';
import '../../../data/serializers/vtt_serializer.dart';
import '../../../domain/entities/subtitle_cue.dart';
import '../../../domain/entities/translation_pack_info.dart';
import '../../../domain/services/background_translation_service.dart';
import '../../../domain/services/subtitle_export_service.dart';
import '../../../native/translation/onnx_translation_engine.dart';
import '../../providers.dart';

class TranslateScreen extends ConsumerStatefulWidget {
  const TranslateScreen({super.key});

  @override
  ConsumerState<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends ConsumerState<TranslateScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- Subtitle File Workflow State ---
  String? _importedFilePath;
  String? _importedFileName;
  List<SubtitleCue> _sourceCues = [];
  List<SubtitleCue> _translatedCues = [];
  bool _isTranslatingSubtitles = false;
  double _translationProgress = 0.0;
  String _translationStatus = '';
  BackgroundTranslationHandle? _translationHandle;

  // --- Quick Dialogue State ---
  final TextEditingController _quickInputController = TextEditingController();
  final TextEditingController _quickOutputController = TextEditingController();
  bool _isQuickTranslating = false;

  // Language pair
  String _sourceLang = 'ja';
  String _targetLang = 'en';

  final List<Map<String, String>> _langs = [
    {'code': 'ja', 'name': 'Japanese'},
    {'code': 'ko', 'name': 'Korean'},
    {'code': 'hi', 'name': 'Hindi'},
    {'code': 'ta', 'name': 'Tamil'},
    {'code': 'en', 'name': 'English'},
    {'code': 'es', 'name': 'Spanish'},
    {'code': 'fr', 'name': 'French'},
    {'code': 'de', 'name': 'German'},
    {'code': 'zh', 'name': 'Chinese'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _quickInputController.dispose();
    _quickOutputController.dispose();
    super.dispose();
  }

  // --- 1. Import Subtitle File ---
  Future<void> _importSubtitleFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'ssa', 'txt'],
      );

      if (result.isEmpty || result.first.path == null) return;

      final path = result.first.path!;
      final file = File(path);
      var content = await file.readAsString();

      // Strip UTF-8 BOM if present
      if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
        content = content.substring(1);
      }

      final ext = p.extension(path).toLowerCase();
      List<SubtitleCue> parsed;

      if (ext == '.vtt') {
        parsed = VttSerializer.parse(content, projectId: 'imported_trans');
      } else if (ext == '.ass' || ext == '.ssa') {
        parsed = AssSerializer.parse(content, projectId: 'imported_trans');
      } else if (ext == '.txt') {
        parsed = TxtSerializer.parse(content, projectId: 'imported_trans');
      } else {
        parsed = SrtSerializer.parse(content, projectId: 'imported_trans');
      }

      if (parsed.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No subtitle cues found in the selected file.')),
          );
        }
        return;
      }

      setState(() {
        _importedFilePath = path;
        _importedFileName = p.basename(path);
        _sourceCues = parsed;
        _translatedCues = [];
        _translationProgress = 0.0;
        _translationStatus = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully loaded $_importedFileName (${parsed.length} cues)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing subtitle file: $e')),
        );
      }
    }
  }

  int _successfulCuesCount = 0;
  int _failedCuesCount = 0;
  Duration? _elapsedDuration;
  Duration? _estimatedRemaining;
  final Set<int> _failedCueIndexes = {};

  String _formatDuration(Duration? d) {
    if (d == null) return '--:--';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  // --- 2. Start Neural Batch Translation ---
  Future<void> _startSubtitleTranslation(TranslationPackInfo? installedPack, {bool retryFailedOnly = false}) async {
    if (_sourceCues.isEmpty) return;
    if (installedPack == null || !installedPack.isInstalled || installedPack.localPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please install the neural language pack for $_sourceLang to $_targetLang first.'),
          action: SnackBarAction(
            label: 'Install',
            onPressed: () => context.push('/language-packs'),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isTranslatingSubtitles = true;
      _translationProgress = 0.0;
      if (!retryFailedOnly) {
        _successfulCuesCount = 0;
        _failedCuesCount = 0;
        _failedCueIndexes.clear();
        _translatedCues.clear();
      }
      _translationStatus = 'Initializing background ONNX neural model...';
    });

    final Map<int, SubtitleCue> currentTranslated = {
      for (var c in _translatedCues) c.cueIndex: c,
    };

    final handle = BackgroundTranslationService.translateCues(
      cues: _sourceCues,
      sourceLang: _sourceLang,
      targetLang: _targetLang,
      packLocalPath: installedPack.localPath!,
      retryCueIndexes: retryFailedOnly ? _failedCueIndexes.toList() : null,
    );
    _translationHandle = handle;

    handle.stream.listen((event) {
      if (!mounted) return;
      if (event is TranslationProgressEvent) {
        setState(() {
          _translationProgress = event.totalCues > 0 ? (event.completedCues / event.totalCues) : 0.0;
          _elapsedDuration = event.elapsed;
          _estimatedRemaining = event.estimatedRemaining;
          _successfulCuesCount = event.completedCues - event.failedCues;
          _failedCuesCount = event.failedCues;
          _translationStatus = 'Translating cue ${event.completedCues} of ${event.totalCues}...';
          if (event.lastTranslatedCue != null) {
            currentTranslated[event.lastTranslatedCue!.cueIndex] = event.lastTranslatedCue!;
            _translatedCues = currentTranslated.values.toList()
              ..sort((a, b) => a.cueIndex.compareTo(b.cueIndex));
          }
        });
      } else if (event is TranslationFinishedEvent) {
        setState(() {
          _isTranslatingSubtitles = false;
          _translatedCues = event.cues;
          _successfulCuesCount = event.successCount;
          _failedCuesCount = event.failedCount;
          _translationStatus = _failedCuesCount > 0
              ? 'Completed: $_successfulCuesCount translated, $_failedCuesCount failed.'
              : 'Translation completed: $_successfulCuesCount cues translated.';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _failedCuesCount > 0
                    ? 'Translated $_successfulCuesCount cues to $_targetLang ($_failedCuesCount failed).'
                    : 'Successfully translated all $_successfulCuesCount cues to $_targetLang!',
              ),
              backgroundColor: _failedCuesCount > 0 ? Colors.amber[800] : const Color(0xFF10B981),
            ),
          );
        }
      } else if (event is TranslationErrorEvent) {
        setState(() {
          _isTranslatingSubtitles = false;
          _translationStatus = 'Error: ${event.error}';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Translation error: ${event.error}'),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    });
  }

  // --- 3. Export Subtitles ---
  Future<void> _exportSubtitles(String format) async {
    if (_translatedCues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No translated subtitles are available. Complete translation first.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    try {
      final settings = ref.read(settingsProvider);
      final baseName = _importedFileName != null
          ? p.basenameWithoutExtension(_importedFileName!)
          : 'subtitles';
      final projectName = '${baseName}_translated_$_targetLang';

      final result = await SubtitleExportService.exportToFile(
        projectName: projectName,
        cues: _translatedCues,
        format: format,
        saveToPublicDownloads: settings.exportToPublicDownloads,
        customTreeUri: settings.customExportDirectoryUri,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully exported ${result.cueCount} translated cues (${result.format}) to:\n${result.pathOrUri}',
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // --- Quick Single Text Translation ---
  Future<void> _performQuickTranslation(TranslationPackInfo? matchingPack) async {
    final text = _quickInputController.text.trim();
    if (text.isEmpty) return;

    if (matchingPack == null || !matchingPack.isInstalled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please install the $_sourceLang to $_targetLang language pack first.'),
          action: SnackBarAction(
            label: 'Install',
            onPressed: () => context.push('/language-packs'),
          ),
        ),
      );
      return;
    }

    setState(() => _isQuickTranslating = true);

    try {
      final result = await OnnxTranslationEngine().translateText(
        text: text,
        sourceLang: _sourceLang,
        targetLang: _targetLang,
        packLocalPath: matchingPack.localPath,
      );

      setState(() {
        _quickOutputController.text = result;
        _isQuickTranslating = false;
      });
    } catch (e) {
      setState(() => _isQuickTranslating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Translation error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packsAsync = ref.watch(languagePacksProvider);

    final matchingPack = packsAsync.maybeWhen(
      data: (packs) => packs.where((p) => p.sourceLang == _sourceLang && p.targetLang == _targetLang).firstOrNull,
      orElse: () => null,
    );
    final isPackInstalled = matchingPack != null && matchingPack.isInstalled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neural Translation Studio'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.subtitles_rounded), text: 'Subtitle File Translation'),
            Tab(icon: Icon(Icons.short_text_rounded), text: 'Quick Text'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Full Subtitle File Translation Workflow
          _buildSubtitleFileTab(theme, matchingPack, isPackInstalled),

          // Tab 2: Quick Dialogue Text
          _buildQuickTextTab(theme, matchingPack, isPackInstalled),
        ],
      ),
    );
  }

  Widget _buildSubtitleFileTab(ThemeData theme, TranslationPackInfo? matchingPack, bool isPackInstalled) {
    final activeCues = _translatedCues.isNotEmpty ? _translatedCues : _sourceCues;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Language Selector Card
        _buildLanguageSelectorCard(theme),

        const SizedBox(height: 12),

        // Neural Model Status Banner
        _buildModelStatusBanner(theme, matchingPack, isPackInstalled),

        const SizedBox(height: 16),

        // Step 1: File Import Section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.file_open_rounded, color: Colors.blueAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Import Subtitle File',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Supports SRT, WebVTT, SubStation Alpha (ASS/SSA), and Text (TXT Mode A/B).',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (_importedFilePath == null) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Choose Subtitle File (.srt, .vtt, .ass, .ssa, .txt)'),
                      onPressed: _importSubtitleFile,
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _importedFileName ?? 'Subtitle File',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_sourceCues.length} cues loaded',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _importSubtitleFile,
                          child: const Text('Replace'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Step 2: Start Translation Button & Progress
        if (_importedFilePath != null) ...[
          if (_isTranslatingSubtitles) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Translating Dialogue (${_sourceLang.toUpperCase()} → ${_targetLang.toUpperCase()})',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        Text('${(_translationProgress * 100).toStringAsFixed(0)}%'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _translationProgress),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Progress: $_successfulCuesCount / ${_sourceCues.length}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              Row(
                                children: [
                                  Text('Translated: $_successfulCuesCount',
                                      style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  Text('Failed: $_failedCuesCount',
                                      style: TextStyle(
                                          color: _failedCuesCount > 0 ? Colors.redAccent : Colors.grey,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Elapsed: ${_formatDuration(_elapsedDuration)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              Text(
                                _estimatedRemaining != null
                                    ? 'Est. remaining: ~${_formatDuration(_estimatedRemaining)}'
                                    : 'Calculating remaining...',
                                style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _translationStatus,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.redAccent),
                          label: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
                          onPressed: () {
                            _translationHandle?.cancel();
                            setState(() {
                              _isTranslatingSubtitles = false;
                              _translationStatus = 'Translation cancelled by user ($_successfulCuesCount cues translated).';
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Column(
              children: [
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.translate_rounded),
                    label: Text(
                      _translatedCues.isNotEmpty ? 'Re-Translate All Subtitles' : 'Translate All Cues with Neural Engine',
                    ),
                    onPressed: isPackInstalled ? () => _startSubtitleTranslation(matchingPack) : null,
                  ),
                ),
                if (_failedCuesCount > 0) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.amber),
                      label: Text('Retry $_failedCuesCount Failed Cues'),
                      onPressed: isPackInstalled
                          ? () => _startSubtitleTranslation(matchingPack, retryFailedOnly: true)
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
        ],

        // Step 3: Export Options
        if (activeCues.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.download_rounded, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'Export Subtitle File',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (_translatedCues.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha(40),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Neural Translated',
                            style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.save_alt_rounded, size: 18),
                          label: const Text('SRT'),
                          onPressed: () => _exportSubtitles('srt'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.save_alt_rounded, size: 18),
                          label: const Text('WebVTT'),
                          onPressed: () => _exportSubtitles('vtt'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.save_alt_rounded, size: 18),
                          label: const Text('ASS'),
                          onPressed: () => _exportSubtitles('ass'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Step 4: Editable Cues Preview List
          Row(
            children: [
              Text(
                'Subtitle Cues (${activeCues.length})',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'Timestamps preserved strictly',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeCues.length,
            itemBuilder: (context, index) {
              final cue = activeCues[index];
              return _buildCueCard(theme, cue, index);
            },
          ),
        ],
      ],
    );
  }

  Widget _buildCueCard(ThemeData theme, SubtitleCue cue, int index) {
    final startStr = TimestampUtils.formatSrt(cue.startMs);
    final endStr = TimestampUtils.formatSrt(cue.endMs);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#${cue.cueIndex}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$startStr  →  $endStr',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (cue.originalText != null && cue.originalText != cue.text) ...[
              const SizedBox(height: 6),
              Text(
                cue.originalText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 6),
            TextFormField(
              initialValue: cue.text,
              maxLines: null,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (newText) {
                if (_translatedCues.isNotEmpty && index < _translatedCues.length) {
                  _translatedCues[index] = _translatedCues[index].copyWith(text: newText);
                } else if (index < _sourceCues.length) {
                  _sourceCues[index] = _sourceCues[index].copyWith(text: newText);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSelectorCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _sourceLang,
                decoration: const InputDecoration(labelText: 'Source Language', border: OutlineInputBorder()),
                items: _langs.map((l) => DropdownMenuItem(value: l['code'], child: Text(l['name']!))).toList(),
                onChanged: (val) => setState(() => _sourceLang = val!),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: () {
                setState(() {
                  final tmp = _sourceLang;
                  _sourceLang = _targetLang;
                  _targetLang = tmp;
                });
              },
            ),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _targetLang,
                decoration: const InputDecoration(labelText: 'Target Language', border: OutlineInputBorder()),
                items: _langs.map((l) => DropdownMenuItem(value: l['code'], child: Text(l['name']!))).toList(),
                onChanged: (val) => setState(() => _targetLang = val!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelStatusBanner(ThemeData theme, TranslationPackInfo? matchingPack, bool isPackInstalled) {
    if (isPackInstalled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Neural model ready: ${matchingPack?.displayName ?? "$_sourceLang to $_targetLang"}',
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withAlpha(100)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Neural pack not installed for $_sourceLang → $_targetLang',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'Download offline model in Language Packs to translate.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: () => context.push('/language-packs'),
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTextTab(ThemeData theme, TranslationPackInfo? matchingPack, bool isPackInstalled) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLanguageSelectorCard(theme),
          const SizedBox(height: 12),
          _buildModelStatusBanner(theme, matchingPack, isPackInstalled),
          const SizedBox(height: 16),
          TextField(
            controller: _quickInputController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Source Dialogue',
              hintText: 'Enter text to test neural inference...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              icon: _isQuickTranslating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.translate_rounded),
              label: const Text('Translate Dialogue'),
              onPressed: (_isQuickTranslating || !isPackInstalled)
                  ? null
                  : () => _performQuickTranslation(matchingPack),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _quickOutputController,
            maxLines: 4,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Neural Translated Output',
              border: OutlineInputBorder(),
              filled: true,
            ),
          ),
        ],
      ),
    );
  }
}
