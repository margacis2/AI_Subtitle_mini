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
  final List<SubtitleCue>? initialCues;
  final Project? initialProject;

  const SubtitleEditorScreen({
    super.key,
    required this.projectId,
    this.initialCues,
    this.initialProject,
  });

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
  final ScrollController _cueScrollController = ScrollController();

  bool _autoScrollEnabled = true;
  bool _isFullscreen = false;
  int? _lastActiveCueIndex;

  @override
  void initState() {
    super.initState();
    if (widget.initialCues != null) {
      _cues = List.from(widget.initialCues!);
      _project = widget.initialProject;
      _isLoading = false;
      if (_project?.mediaPath != null && File(_project!.mediaPath!).existsSync()) {
        _initVideoPlayer(_project!.mediaPath!);
      }
    } else {
      _loadProjectAndCues();
    }
  }

  Future<void> _loadProjectAndCues() async {
    setState(() => _isLoading = true);
    final p = await _db.getProject(widget.projectId);
    final list = await _db.getCuesForProject(widget.projectId);

    if (mounted) {
      setState(() {
        _project = p;
        _cues = list;
        _isLoading = false;
      });
    }

    if (p?.mediaPath != null && File(p!.mediaPath!).existsSync()) {
      _initVideoPlayer(p.mediaPath!);
    }
  }

  void _initVideoPlayer(String path) {
    _videoController = VideoPlayerController.file(File(path))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _videoController?.addListener(_onVideoTick);
        }
      });
  }

  void _onVideoTick() {
    if (_videoController != null && mounted) {
      final pos = _videoController!.value.position.inMilliseconds;
      if ((pos - _currentVideoMs).abs() > 80) {
        setState(() {
          _currentVideoMs = pos;
        });
        _syncScrollWithVideo();
      }
    }
  }

  void _syncScrollWithVideo() {
    if (!_autoScrollEnabled || !_cueScrollController.hasClients) return;

    final filtered = _filteredCues;
    final activeIndex = filtered.indexWhere((c) => _currentVideoMs >= c.startMs && _currentVideoMs <= c.endMs);
    if (activeIndex != -1 && activeIndex != _lastActiveCueIndex) {
      _lastActiveCueIndex = activeIndex;
      // Estimate item height for smooth centering: ~88px
      final targetOffset = (activeIndex * 88.0 - 100.0).clamp(
        0.0,
        _cueScrollController.position.maxScrollExtent,
      );
      _cueScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  List<SubtitleCue> get _filteredCues {
    if (_searchQuery.isEmpty) return _cues;
    return _cues.where((c) => c.text.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
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

    // Scroll to new cue
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cueScrollController.hasClients) {
        _cueScrollController.animateTo(
          _cueScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
                maxLines: 4,
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
    _cueScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filteredCues = _filteredCues;

    return Scaffold(
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(_project?.name ?? 'Subtitle Editor', maxLines: 1, overflow: TextOverflow.ellipsis),
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
      body: SafeArea(
        top: !_isFullscreen,
        bottom: true,
        left: true,
        right: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_isFullscreen) {
              return _buildFullscreenPlayer(theme);
            }

            // Decide layout based on available width vs height
            final isLandscape = constraints.maxWidth > constraints.maxHeight && constraints.maxWidth >= 550;

            if (isLandscape) {
              // LANDSCAPE: Responsive Side-by-Side Coexistence
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Side: Video Player (52% width)
                  Expanded(
                    flex: 11,
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: _buildVideoPreview(constraints, isLandscape: true),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  // Right Side: Scrollable Subtitle Panel (48% width)
                  Expanded(
                    flex: 10,
                    child: _buildSubtitlePanel(theme, filteredCues, isLandscape: true),
                  ),
                ],
              );
            } else {
              // PORTRAIT: Vertically Arranged Layout with Height Bounds
              return Column(
                children: [
                  // Top: Video Player with bounded height (max 38% of available height)
                  Container(
                    color: Colors.black,
                    constraints: BoxConstraints(
                      maxHeight: (constraints.maxHeight * 0.38).clamp(160.0, 320.0),
                    ),
                    width: double.infinity,
                    child: Center(
                      child: _buildVideoPreview(constraints, isLandscape: false),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1),
                  // Bottom: Subtitle Panel taking ALL remaining height
                  Expanded(
                    child: _buildSubtitlePanel(theme, filteredCues, isLandscape: false),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  // --- VIDEO PLAYER PREVIEW WIDGET ---
  Widget _buildVideoPreview(BoxConstraints constraints, {required bool isLandscape}) {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_outlined, size: 48, color: Colors.white54),
            const SizedBox(height: 12),
            Text(
              _project?.mediaPath != null ? 'Initializing media player...' : 'No media attached to project',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final rawAspectRatio = _videoController!.value.aspectRatio;
    final aspectRatio = (rawAspectRatio > 0) ? rawAspectRatio : (16 / 9);

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_videoController!),

          // Live Subtitle Overlay
          if (_activeCue != null)
            Align(
              alignment: _style.alignment.alignment,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
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
                    fontSize: isLandscape ? (_style.fontSize * 1.1) : _style.fontSize,
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

          // Video Playback Controls Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    iconSize: 22,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _videoController!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
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
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: _currentVideoMs.toDouble().clamp(
                              0.0,
                              _videoController!.value.duration.inMilliseconds.toDouble(),
                            ),
                        min: 0.0,
                        max: _videoController!.value.duration.inMilliseconds.toDouble(),
                        onChanged: (val) {
                          _videoController!.seekTo(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                  ),
                  Text(
                    '${TimestampUtils.formatDuration(_currentVideoMs)} / ${TimestampUtils.formatDuration(_videoController!.value.duration.inMilliseconds)}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      color: Colors.white,
                    ),
                    tooltip: _isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                    onPressed: () {
                      setState(() => _isFullscreen = !_isFullscreen);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- FULLSCREEN VIDEO PLAYER ---
  Widget _buildFullscreenPlayer(ThemeData theme) {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: _buildVideoPreview(
              const BoxConstraints(),
              isLandscape: true,
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => setState(() => _isFullscreen = false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- SUBTITLE PANEL (HEADER & SCROLLABLE LIST) ---
  Widget _buildSubtitlePanel(ThemeData theme, List<SubtitleCue> filteredCues, {required bool isLandscape}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Subtitle Panel Header Controls
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(bottom: BorderSide(color: theme.dividerColor.withAlpha(80))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search cues...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _addNewCue,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${filteredCues.length} Cues (${_cues.length} total)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() => _autoScrollEnabled = !_autoScrollEnabled);
                      if (_autoScrollEnabled) _syncScrollWithVideo();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _autoScrollEnabled ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                            size: 14,
                            color: _autoScrollEnabled ? theme.colorScheme.primary : theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _autoScrollEnabled ? 'Follow Playhead' : 'Manual Scroll',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _autoScrollEnabled ? theme.colorScheme.primary : theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Scrollable Cues List
        Expanded(
          child: filteredCues.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.subtitles_off_rounded, size: 40, color: theme.colorScheme.outline),
                        const SizedBox(height: 10),
                        Text(
                          _cues.isEmpty ? 'No subtitles in project' : 'No cues match your search',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is UserScrollNotification) {
                      // Don't auto-scroll while user is actively interacting with list
                      _autoScrollEnabled = false;
                    }
                    return false;
                  },
                  child: ListView.separated(
                    controller: _cueScrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 32),
                    itemCount: filteredCues.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final cue = filteredCues[index];
                      final isCurrent = _currentVideoMs >= cue.startMs && _currentVideoMs <= cue.endMs;
                      return _buildCueTile(theme, cue, index, isCurrent);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // --- SUBTITLE CUE ITEM TILE ---
  Widget _buildCueTile(ThemeData theme, SubtitleCue cue, int index, bool isCurrent) {
    return Card(
      elevation: isCurrent ? 2 : 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withAlpha(80),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      color: isCurrent ? theme.colorScheme.primaryContainer.withAlpha(90) : theme.colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (_videoController != null && _videoController!.value.isInitialized) {
            _videoController!.seekTo(Duration(milliseconds: cue.startMs));
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#${cue.cueIndex}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCurrent ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${TimestampUtils.formatSrt(cue.startMs)} → ${TimestampUtils.formatSrt(cue.endMs)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit cue',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editCueDialog(cue, index),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                cue.text,
                softWrap: true,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13.5,
                ),
              ),
              if (cue.originalText != null && cue.originalText != cue.text) ...[
                const SizedBox(height: 4),
                Text(
                  cue.originalText!,
                  softWrap: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
