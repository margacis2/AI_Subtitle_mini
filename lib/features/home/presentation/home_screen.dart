import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utilities/timestamp_utils.dart';
import '../../../domain/entities/project.dart';
import '../../batch_queue/presentation/batch_queue_screen.dart';
import '../../model_library/presentation/model_library_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsProvider);
    final jobsAsync = ref.watch(jobsProvider);
    final theme = Theme.of(context);

    final activeJobsCount = jobsAsync.maybeWhen(
      data: (jobs) => jobs.where((j) => j.stage.isActive).length,
      orElse: () => 0,
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withAlpha(60),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/images/app_logo.png', fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'AI Sub Mini',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.4,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '100% On-Device AI',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: activeJobsCount > 0,
              backgroundColor: const Color(0xFF6366F1),
              label: Text('$activeJobsCount', style: const TextStyle(fontWeight: FontWeight.bold)),
              child: const Icon(Icons.flash_on_rounded),
            ),
            tooltip: 'Live Processing Queue',
            onPressed: () => setState(() => _currentIndex = 2),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (val) {
              if (val == 'new_project') context.push('/new-project');
              if (val == 'diagnostics') context.push('/diagnostics');
              if (val == 'settings') context.push('/settings');
              if (val == 'about') context.push('/about');
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new_project',
                child: Row(
                  children: [
                    Icon(Icons.add_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('New Project'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'diagnostics',
                child: Row(
                  children: [
                    Icon(Icons.monitor_heart_outlined, size: 20),
                    SizedBox(width: 10),
                    Text('Diagnostics'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('Settings'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('About & Privacy'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _buildBodyTab(_currentIndex, projectsAsync, theme),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.movie_creation_outlined),
            selectedIcon: Icon(Icons.movie_creation_rounded),
            label: 'Projects',
          ),
          const NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology_rounded),
            label: 'AI Models',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: activeJobsCount > 0,
              label: Text('$activeJobsCount'),
              child: const Icon(Icons.layers_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: activeJobsCount > 0,
              label: Text('$activeJobsCount'),
              child: const Icon(Icons.layers_rounded),
            ),
            label: 'Queue',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Studio',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Subtitles'),
              onPressed: () => context.push('/new-project'),
            )
          : null,
    );
  }

  Widget _buildBodyTab(int index, AsyncValue<List<Project>> projectsAsync, ThemeData theme) {
    switch (index) {
      case 0:
        return _buildProjectsTab(projectsAsync, theme);
      case 1:
        return const ModelLibraryScreen();
      case 2:
        return const BatchQueueScreen();
      case 3:
        return const SettingsScreen();
      default:
        return _buildProjectsTab(projectsAsync, theme);
    }
  }

  Widget _buildProjectsTab(AsyncValue<List<Project>> projectsAsync, ThemeData theme) {
    return projectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text('Error loading projects: $err', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => ref.read(projectsProvider.notifier).loadProjects(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (projects) {
        final filtered = projects.where((p) {
          if (_searchQuery.isEmpty) return true;
          return p.name.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        return RefreshIndicator(
          onRefresh: () => ref.read(projectsProvider.notifier).loadProjects(),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Fast Quick Import Card
              _QuickActionBanner(onTap: () => context.push('/new-project')),
              const SizedBox(height: 16),

              // Search Bar if projects exist
              if (projects.isNotEmpty) ...[
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search subtitle projects...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
                const SizedBox(height: 16),
              ],

              if (filtered.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withAlpha(50),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.subtitles_off_rounded,
                          size: 38,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        projects.isEmpty ? 'No Projects Yet' : 'No Matching Projects',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        projects.isEmpty
                            ? 'Import a video or audio file to transcribe speech with offline AI and export subtitles.'
                            : 'Try a different search query.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'RECENT PROJECTS (${filtered.length})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ...filtered.map((project) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ModernProjectCard(project: project),
                    )),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _QuickActionBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _QuickActionBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withAlpha(80),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transcribe Video / Audio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Offline Whisper speech recognition & neural translation',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernProjectCard extends ConsumerWidget {
  final Project project;
  const _ModernProjectCard({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy • HH:mm');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/editor/${project.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withAlpha(35),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      project.mediaPath != null ? Icons.videocam_rounded : Icons.subtitles_rounded,
                      color: const Color(0xFF818CF8),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          dateFormat.format(project.updatedAt),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onSelected: (val) {
                      if (val == 'open') context.push('/editor/${project.id}');
                      if (val == 'delete') _confirmDelete(context, ref);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'open',
                        child: Row(
                          children: [
                            Icon(Icons.edit_note_rounded, size: 20),
                            SizedBox(width: 8),
                            Text('Open Editor'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _BadgePill(
                    icon: Icons.subtitles_rounded,
                    label: '${project.cueCount} Cues',
                    color: const Color(0xFF6366F1),
                  ),
                  if (project.durationMs != null && project.durationMs! > 0)
                    _BadgePill(
                      icon: Icons.timer_outlined,
                      label: TimestampUtils.formatDuration(project.durationMs!),
                      color: const Color(0xFF06B6D4),
                    ),
                  _BadgePill(
                    icon: Icons.mic_none_rounded,
                    label: project.sourceLanguage.toUpperCase(),
                    color: const Color(0xFF10B981),
                  ),
                  if (project.targetLanguage != null)
                    _BadgePill(
                      icon: Icons.translate_rounded,
                      label: '→ ${project.targetLanguage!.toUpperCase()}',
                      color: const Color(0xFF8B5CF6),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: Text('Are you sure you want to delete "${project.name}" and all associated subtitles?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(projectsProvider.notifier).deleteProject(project.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _BadgePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
