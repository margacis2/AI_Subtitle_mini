import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/utilities/timestamp_utils.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/entities/project.dart';
import '../../../domain/entities/subtitle_cue.dart';
import '../../../domain/entities/subtitle_style.dart';
import '../../../domain/services/subtitle_export_service.dart';
import '../../providers.dart';

class SubtitleEditorScreen extends ConsumerStatefulWidget {
  final String projectId;

  const SubtitleEditorScreen({super.key, required this.projectId});

  @override
  ConsumerState<SubtitleEditorScreen> createState() => _SubtitleEditorScreenState();
}

class _SubtitleEditorScreenState extends ConsumerState<SubtitleEditorScreen> {
  final AppDatabase _db = AppDatabase();
  Project? _project;
  List<SubtitleCue> _cues = [];
  bool _isLoading = true;

  VideoPlayerController? _videoController;
  SubtitleStyle _style = const SubtitleStyle();
  int _currentVideoMs = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProjectAndCues();
  }

  Future<void> _loadProjectAndCues() async {
    setState(() => _isLoading = true);
    final p = await _db.getProject(widget.projectId);
    final list = await _db.getCuesForProject(widget.projectId);

    setState(() {
      _project = p;
      _cues = list;
      _isLoading = false;
    });

    if (p?.mediaPath != null && File(p!.mediaPath!).existsSync()) {
      _initVideoPlayer(p.mediaPath!);
    }
  }

  void _initVideoPlayer(String path) {
    _videoController = VideoPlayerController.file(File(path))
      ..initialize().then((_) {
        setState(() {});
        _videoController?.addListener(_onVideoTick);
      });
  }

  void _onVideoTick() {
    if (_videoController != null && mounted) {
      final pos = _videoController!.value.position.inMilliseconds;
      if ((pos - _currentVideoMs).abs() > 100) {
        setState(() {
          _currentVideoMs = pos;
        });
      }
    }
  }

  SubtitleCue? get _activeCue {
    for (final c in _cues) {
      if (_currentVideoMs >= c.startMs && _currentVideoMs <= c.endMs) {
        return c;
      }
    }
    return null;
  }

  Future<void> _saveCues() async {
    await _db.replaceCuesForProject(widget.projectId, _cues);
    ref.read(projectsProvider.notifier).loadProjects();
  }

  void _addNewCue() {
    final lastEnd = _cues.isNotEmpty ? _cues.last.endMs + 200 : 0;
    final newCue = SubtitleCue(
      projectId: widget.projectId,
      cueIndex: _cues.length + 1,
      startMs: lastEnd,
      endMs: lastEnd + 3000,
      text: 'New subtitle cue text',
    );
    setState(() {
      _cues.add(newCue);
    });
    _saveCues();
  }

  void _editCueDialog(SubtitleCue cue, int index) {
    final textCtrl = TextEditingController(text: cue.text);
    final startCtrl = TextEditingController(text: TimestampUtils.formatSrt(cue.startMs));
    final endCtrl = TextEditingController(text: TimestampUtils.formatSrt(cue.endMs));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Cue #${cue.cueIndex}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Subtitle Text', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: startCtrl,
                      decoration: const InputDecoration(labelText: 'Start Time (HH:mm:ss,SSS)', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: endCtrl,
                      decoration: const InputDecoration(labelText: 'End Time (HH:mm:ss,SSS)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _cues.removeAt(index);
                // reindex
                for (int i = 0; i < _cues.length; i++) {
                  _cues[i] = _cues[i].copyWith(cueIndex: i + 1);
                }
              });
              _saveCues();
            },
            child: const Text('Delete Cue', style: TextStyle(color: Colors.redAccent)),
          ),
          FilledButton(
            onPressed: () {
              final newStart = TimestampUtils.parseSrt(startCtrl.text);
              final newEnd = TimestampUtils.parseSrt(endCtrl.text);
              setState(() {
                _cues[index] = cue.copyWith(
                  text: textCtrl.text.trim(),
                  startMs: newStart,
                  endMs: newEnd,
                );
              });
              _saveCues();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _shiftTimesDialog() {
    final shiftCtrl = TextEditingController(text: '500');
    bool shiftForward = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Shift Timestamps'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Adjust timing of all cues simultaneously:'),
              const SizedBox(height: 12),
              TextField(
                controller: shiftCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Milliseconds (ms)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('+ Forward (+ms)'),
                    selected: shiftForward,
                    onSelected: (val) => setDialogState(() => shiftForward = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('- Backward (-ms)'),
                    selected: !shiftForward,
                    onSelected: (val) => setDialogState(() => shiftForward = false),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final ms = int.tryParse(shiftCtrl.text) ?? 0;
                final delta = shiftForward ? ms : -ms;
                setState(() {
                  _cues = _cues.map((c) {
                    return c.copyWith(
                      startMs: (c.startMs + delta).clamp(0, 86400000),
                      endMs: (c.endMs + delta).clamp(0, 86400000),
                    );
                  }).toList();
                });
                _saveCues();
                Navigator.pop(ctx);
              },
              child: const Text('Apply Shift'),
            ),
          ],
        ),
      ),
    );
  }

  void _openStyleSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtitle Styling Controls', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              // Font size slider
              Text('Font Size: ${_style.fontSize.toInt()} pt'),
              Slider(
                value: _style.fontSize,
                min: 12,
                max: 36,
                divisions: 24,
                onChanged: (val) {
                  setSheetState(() => _style = _style.copyWith(fontSize: val));
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              // Text Bold & Italic
              Row(
                children: [
                  FilterChip(
                    label: const Text('Bold'),
                    selected: _style.isBold,
                    onSelected: (val) {
                      setSheetState(() => _style = _style.copyWith(isBold: val));
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Italic'),
                    selected: _style.isItalic,
                    onSelected: (val) {
                      setSheetState(() => _style = _style.copyWith(isItalic: val));
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Alignment
              const Text('Alignment:'),
              Wrap(
                spacing: 8,
                children: SubtitleAlignment.values.map((align) {
                  return ChoiceChip(
                    label: Text(align.displayName),
                    selected: _style.alignment == align,
                    onSelected: (sel) {
                      if (sel) {
                        setSheetState(() => _style = _style.copyWith(alignment: align));
                        setState(() {});
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportSubtitles(String format) async {
    try {
      final file = await SubtitleExportService.exportToFile(
        projectName: _project?.name ?? 'Subtitles',
        cues: _cues,
        format: format,
        style: _style,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported successfully to: ${file.path}'),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filteredCues = _searchQuery.isEmpty
        ? _cues
        : _cues.where((c) => c.text.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_project?.name ?? 'Subtitle Editor', maxLines: 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.style_outlined),
            tooltip: 'Subtitle Styling',
            onPressed: _openStyleSheet,
          ),
          IconButton(
            icon: const Icon(Icons.more_time_rounded),
            tooltip: 'Shift Timings',
            onPressed: _shiftTimesDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export Subtitles',
            onSelected: _exportSubtitles,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'srt', child: Text('Export SubRip (.srt)')),
              PopupMenuItem(value: 'vtt', child: Text('Export WebVTT (.vtt)')),
              PopupMenuItem(value: 'ass', child: Text('Export Advanced SSA (.ass)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. VIDEO PREVIEW WITH LIVE SUBTITLE OVERLAY
          if (_videoController != null && _videoController!.value.isInitialized) ...[
            AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  VideoPlayer(_videoController!),
                  // Live Subtitle Overlay
                  if (_activeCue != null)
                    Positioned.fill(
                      child: Align(
                        alignment: _style.alignment.alignment,
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _style.backgroundColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _activeCue!.text,
                            textAlign: _style.alignment.textAlign,
                            style: TextStyle(
                              fontFamily: _style.fontFamily,
                              fontSize: _style.fontSize,
                              fontWeight: _style.isBold ? FontWeight.bold : FontWeight.normal,
                              fontStyle: _style.isItalic ? FontStyle.italic : FontStyle.normal,
                              color: _style.textColor,
                              shadows: [
                                Shadow(
                                  color: _style.outlineColor,
                                  blurRadius: _style.outlineWidth * 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Video Play/Pause Overlay Controls
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.black45,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              setState(() {
                                if (_videoController!.value.isPlaying) {
                                  _videoController!.pause();
                                } else {
                                  _videoController!.play();
                                }
                              });
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: _currentVideoMs.toDouble().clamp(0.0, _videoController!.value.duration.inMilliseconds.toDouble()),
                              min: 0.0,
                              max: _videoController!.value.duration.inMilliseconds.toDouble(),
                              onChanged: (val) {
                                _videoController!.seekTo(Duration(milliseconds: val.toInt()));
                              },
                            ),
                          ),
                          Text(
                            '${TimestampUtils.formatDuration(_currentVideoMs)} / ${TimestampUtils.formatDuration(_videoController!.value.duration.inMilliseconds)}',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 2. SEARCH BAR & STATS
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search cues...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${_cues.length} Cues', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          // 3. CUES LIST
          Expanded(
            child: filteredCues.isEmpty
                ? const Center(child: Text('No subtitle cues found.'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    itemCount: filteredCues.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final cue = filteredCues[index];
                      final isCurrent = _currentVideoMs >= cue.startMs && _currentVideoMs <= cue.endMs;

                      return Card(
                        color: isCurrent ? theme.colorScheme.primaryContainer.withAlpha(80) : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCurrent ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                            foregroundColor: isCurrent ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                            child: Text('${cue.cueIndex}'),
                          ),
                          title: Text(cue.text, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${TimestampUtils.formatSrt(cue.startMs)} → ${TimestampUtils.formatSrt(cue.endMs)} (${cue.durationMs}ms)',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                          ),
                          trailing: const Icon(Icons.edit_outlined, size: 20),
                          onTap: () {
                            if (_videoController != null && _videoController!.value.isInitialized) {
                              _videoController!.seekTo(Duration(milliseconds: cue.startMs));
                            }
                            _editCueDialog(cue, index);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add Cue'),
        onPressed: _addNewCue,
      ),
    );
  }
}
