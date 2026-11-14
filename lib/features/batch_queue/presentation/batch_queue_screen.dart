import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        title: const Text('Batch Processing Queue'),
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
        error: (err, _) => Center(child: Text('Error loading jobs: $err')),
        data: (jobs) {
          if (jobs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.done_all_rounded, size: 72, color: theme.colorScheme.primary.withAlpha(150)),
                    const SizedBox(height: 16),
                    Text(
                      'Queue is Empty',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'All background transcription and translation tasks have finished.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
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
              return _JobCard(
                job: job,
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
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

class _JobCard extends StatelessWidget {
  final ProcessingJob job;
  final VoidCallback onTap;

  const _JobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color statusColor;
    IconData statusIcon;

    switch (job.stage) {
      case JobStage.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        break;
      case JobStage.failed:
        statusColor = Colors.redAccent;
        statusIcon = Icons.error_outline;
        break;
      case JobStage.cancelled:
        statusColor = Colors.orange;
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = theme.colorScheme.primary;
        statusIcon = Icons.sync_rounded;
        break;
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          job.stage.displayName,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(job.progress * 100).toInt()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              if (job.stage.isActive) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: job.progress > 0 ? job.progress : null),
                if (job.currentStep != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    job.currentStep!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
