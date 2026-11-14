import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/user_settings.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. CONTENT MASKING POLICY
          _buildHeader(theme, 'PROFANITY & MASKING POLICY'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Masking Style:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...CensorMaskType.values.map((type) {
                    return RadioListTile<CensorMaskType>(
                      contentPadding: EdgeInsets.zero,
                      value: type,
                      groupValue: settings.censorMaskType,
                      title: Text(type.displayName, style: const TextStyle(fontSize: 14)),
                      onChanged: (val) {
                        if (val != null) notifier.setCensorMaskType(val);
                      },
                    );
                  }),
                  if (settings.censorMaskType == CensorMaskType.placeholder) ...[
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Custom Placeholder Text',
                        border: OutlineInputBorder(),
                      ),
                      controller: TextEditingController(text: settings.censorPlaceholder),
                      onChanged: (val) => notifier.updateSettings(settings.copyWith(censorPlaceholder: val)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. EXPORT & STORAGE
          _buildHeader(theme, 'EXPORT & STORAGE PREFERENCES'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: settings.defaultExportFormat,
                    decoration: const InputDecoration(
                      labelText: 'Default Export Format',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'srt', child: Text('SubRip Subtitle (.srt)')),
                      DropdownMenuItem(value: 'vtt', child: Text('WebVTT (.vtt)')),
                      DropdownMenuItem(value: 'ass', child: Text('Advanced SubStation Alpha (.ass)')),
                    ],
                    onChanged: (val) {
                      if (val != null) notifier.setExportFormat(val);
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Save to Public Downloads'),
                    subtitle: const Text('Export files to Downloads/AI Subtitles/ for easy sharing'),
                    value: settings.exportToPublicDownloads,
                    onChanged: (val) => notifier.updateSettings(settings.copyWith(exportToPublicDownloads: val)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. APPEARANCE & HARDWARE
          _buildHeader(theme, 'APPEARANCE & PERFORMANCE'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<ThemeMode>(
                    initialValue: settings.themeMode,
                    decoration: const InputDecoration(
                      labelText: 'Application Theme',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark Mode (Recommended)')),
                      DropdownMenuItem(value: ThemeMode.light, child: Text('Light Mode')),
                      DropdownMenuItem(value: ThemeMode.system, child: Text('Follow System Theme')),
                    ],
                    onChanged: (val) {
                      if (val != null) notifier.setThemeMode(val);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Inference Thread Count: ${settings.threadCount} Cores', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: settings.threadCount.toDouble(),
                    min: 1,
                    max: 8,
                    divisions: 7,
                    label: '${settings.threadCount}',
                    onChanged: (val) => notifier.setThreadCount(val.toInt()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
