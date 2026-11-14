import 'dart:io';
import 'package:path/path.dart' as p;

class MediaMetadata {
  final String fileName;
  final String filePath;
  final int fileSizeBytes;
  final int? durationMs;
  final String? audioCodec;
  final int? sampleRate;
  final int? channels;
  final bool hasVideo;

  const MediaMetadata({
    required this.fileName,
    required this.filePath,
    required this.fileSizeBytes,
    this.durationMs,
    this.audioCodec,
    this.sampleRate,
    this.channels,
    this.hasVideo = true,
  });

  String get formattedFileSize {
    final mb = fileSizeBytes / (1024 * 1024);
    if (mb >= 1000) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class MediaInspector {
  static final MediaInspector _instance = MediaInspector._internal();
  factory MediaInspector() => _instance;
  MediaInspector._internal();

  Future<MediaMetadata> inspectMedia(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final size = await file.length();
    final name = p.basename(filePath);
    final ext = p.extension(filePath).toLowerCase();

    final isAudioOnly = ['.mp3', '.wav', '.m4a', '.aac', '.flac', '.ogg'].contains(ext);

    int? durationMs;
    try {
      final probeResult = await Process.run('ffprobe', [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        filePath,
      ]);
      if (probeResult.exitCode == 0) {
        final sec = double.tryParse((probeResult.stdout as String).trim());
        if (sec != null) {
          durationMs = (sec * 1000).toInt();
        }
      }
    } catch (_) {}

    return MediaMetadata(
      fileName: name,
      filePath: filePath,
      fileSizeBytes: size,
      durationMs: durationMs,
      hasVideo: !isAudioOnly,
    );
  }
}
