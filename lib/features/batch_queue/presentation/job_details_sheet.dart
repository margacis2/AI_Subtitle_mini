import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/processing_job.dart';

class JobDetailsSheet extends StatelessWidget {
  final ProcessingJob job;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const JobDetailsSheet({
    super.key,
    required this.job,
    required this.onRetry,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy • HH:mm:ss');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Job Details', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(job.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text('ID: ${job.id}'),
          ),
          const Divider(),
          _infoRow('Current Stage', job.stage.displayName),
          _infoRow('Progress', '${(job.progress * 100).toInt()}%'),
          if (job.currentStep != null) _infoRow('Current Step', job.currentStep!),
          _infoRow('Created', dateFormat.format(job.createdAt)),
          if (job.completedAt != null) _infoRow('Completed', dateFormat.format(job.completedAt!)),
          _infoRow('Retry Count', '${job.retryCount}'),
          if (job.errorDetails != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withAlpha(80)),
              ),
              child: Text(
                'Error: ${job.errorDetails}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              if (job.stage == JobStage.failed) ...[
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry Job'),
                    onPressed: () {
                      Navigator.pop(context);
                      onRetry();
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (job.stage.isActive) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel Job'),
                    onPressed: () {
                      Navigator.pop(context);
                      onCancel();
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              IconButton.outlined(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: 'Delete Job Record',
                onPressed: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
