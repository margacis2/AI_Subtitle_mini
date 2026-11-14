import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('About & Privacy'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.subtitles_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'AI Subtitle Studio',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0 (Open Source Edition)',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            color: Colors.green.withAlpha(20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.green.withAlpha(60)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.security_rounded, color: Colors.green),
                      SizedBox(width: 10),
                      Text(
                        'LOCAL PROCESSING GUARANTEE',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'AI Subtitle Studio processes all media, audio, and subtitle files exclusively on your local device hardware using on-device C/C++ neural inference (whisper.cpp). Your personal movies, voice recordings, and subtitle contents are never uploaded to any server, API, or third-party cloud service.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: const Text('Open Source Components'),
                  subtitle: const Text('whisper.cpp, FFmpeg, ONNX Runtime Mobile, Flutter, SQLite'),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'AI Subtitle Studio',
                      applicationVersion: '1.0.0',
                      applicationIcon: const Icon(Icons.subtitles_rounded),
                    );
                  },
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.copyright_rounded),
                  title: Text('License'),
                  subtitle: Text('Released under the MIT License'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
