import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/entities/processing_job.dart';
import '../../providers.dart';
import 'job_details_sheet.dart';

class BatchQueueScreen extends ConsumerWidget {
  const BatchQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(jobsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Processing Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: 'Clear Finished Jobs',
            onPressed: () => ref.read(jobsProvider.notifier).clearCompleted(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Queue',
            onPressed: () => ref.read(jobsProvider.notifier).loadJobs(),
          ),
        ],
      ),
      body: jobsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text('Error loading queue: $err', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => ref.read(jobsProvider.notifier).loadJobs(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (jobs) {
          if (jobs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.task_alt_rounded, size: 44, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Queue is Idle',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'All background transcription and translation jobs have finished.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Start New Conversion'),
                      onPressed: () => context.push('/new-project'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final job = jobs[index];
              return _ModernJobCard(
                job: job,
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: theme.cardTheme.color,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (ctx) => JobDetailsSheet(
                      job: job,
                      onRetry: () => ref.read(jobsProvider.notifier).retryJob(job.id),
                      onCancel: () => ref.read(jobsProvider.notifier).cancelJob(job.id),
                      onDelete: () => ref.read(jobsProvider.notifier).deleteJob(job.id),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ModernJobCard extends ConsumerWidget {
  final ProcessingJob job;
  final VoidCallback onTap;

  const _ModernJobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (job.stage) {
      case JobStage.queued:
        statusColor = const Color(0xFFF59E0B); // Amber
        statusIcon = Icons.hourglass_top_rounded;
        statusLabel = 'In Queue';
        break;
      case JobStage.preparing:
        statusColor = const Color(0xFF06B6D4); // Cyan
        statusIcon = Icons.tune_rounded;
        statusLabel = 'Preparing';
        break;
      case JobStage.extractingAudio:
        statusColor = const Color(0xFF06B6D4); // Cyan
        statusIcon = Icons.graphic_eq_rounded;
        statusLabel = 'Extracting Audio';
        break;
      case JobStage.running:
      case JobStage.transcribing:
        statusColor = const Color(0xFF6366F1); // Indigo
        statusIcon = Icons.record_voice_over_rounded;
        statusLabel = 'Transcribing Speech';
        break;
      case JobStage.translating:
        statusColor = const Color(0xFF8B5CF6); // Violet
        statusIcon = Icons.translate_rounded;
        statusLabel = 'Neural Translation';
        break;
      case JobStage.formatting:
        statusColor = const Color(0xFF3B82F6); // Blue
        statusIcon = Icons.auto_awesome_rounded;
        statusLabel = 'Formatting Cues';
        break;
      case JobStage.paused:
        statusColor = Colors.orangeAccent;
        statusIcon = Icons.pause_circle_outline_rounded;
        statusLabel = 'Paused';
        break;
      case JobStage.recoverable:
        statusColor = const Color(0xFFF59E0B); // Amber
        statusIcon = Icons.replay_rounded;
        statusLabel = 'Interrupted (Recoverable)';
        break;
      case JobStage.completed:
        statusColor = const Color(0xFF10B981); // Emerald
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'Completed';
        break;
      case JobStage.failed:
        statusColor = const Color(0xFFEF4444); // Red
        statusIcon = Icons.error_rounded;
        statusLabel = 'Failed';
        break;
      case JobStage.cancelled:
        statusColor = Colors.grey;
        statusIcon = Icons.cancel_rounded;
        statusLabel = 'Cancelled';
        break;
    }

    final isProcessing = job.stage.isActive;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (isProcessing) ...[
                              const SizedBox(width: 8),
                              Text(
                                '${(job.progress * 100).toInt()}%',
                                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (job.stage == JobStage.completed)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFF10B981).withAlpha(40),
                        foregroundColor: const Color(0xFF10B981),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('Open'),
                      onPressed: () => context.push('/editor/${job.projectId}'),
                    )
                  else if (job.stage == JobStage.recoverable)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFFF59E0B).withAlpha(40),
                        foregroundColor: const Color(0xFFF59E0B),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: const Text('Resume'),
                      onPressed: () => ref.read(jobsProvider.notifier).resumeJob(job.id),
                    )
                  else if (job.stage == JobStage.failed)
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.amber),
                      tooltip: 'Retry Job',
                      onPressed: () => ref.read(jobsProvider.notifier).retryJob(job.id),
                    )
                  else if (isProcessing)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                ],
              ),
              if (job.currentStep != null) ...[
                const SizedBox(height: 12),
                Text(
                  job.currentStep!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (isProcessing) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: job.progress > 0 ? job.progress : null,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor.withAlpha(40)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.timer_outlined, size: 14, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                'Elapsed: ${job.formattedElapsed ?? "00:00"}',
                                style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          Text(
                            job.formattedEta != null
                                ? 'Remaining: ~${job.formattedEta}'
                                : (job.elapsedSeconds != null && job.elapsedSeconds! > 5
                                    ? 'Calculating remaining...'
                                    : 'Estimating...'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (job.formattedEstimatedTotal != null || job.formattedAudioDuration != null || (job.totalChunks != null && job.totalChunks! > 1)) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (job.formattedAudioDuration != null)
                              Text(
                                'Audio: ${job.formattedAudioDuration}',
                                style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
                              ),
                            if (job.currentChunk != null && job.totalChunks != null && job.totalChunks! > 1)
                              Text(
                                'Chunk: ${job.currentChunk} / ${job.totalChunks}',
                                style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500),
                              ),
                            if (job.formattedEstimatedTotal != null)
                              Text(
                                'Est. Total: ${job.formattedEstimatedTotal}',
                                style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (job.errorDetails != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    job.errorDetails!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
