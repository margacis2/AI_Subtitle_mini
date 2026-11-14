import 'dart:io';
import 'dart:typed_data';
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

  String get formattedDuration {
    if (durationMs == null || durationMs! <= 0) return '00:00';
    final totalSec = durationMs! ~/ 1000;
    final minutes = (totalSec ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSec % 60).toString().padLeft(2, '0');
    final hours = totalSec ~/ 3600;
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
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

    // 1. Try ffprobe if available in environment
    try {
      final probeResult = await Process.run('ffprobe', [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        filePath,
      ]);
      if (probeResult.exitCode == 0) {
        final sec = double.tryParse((probeResult.stdout as String).trim());
        if (sec != null && sec > 0) {
          durationMs = (sec * 1000).toInt();
        }
      }
    } catch (_) {}

    // 2. Pure-Dart embedded metadata parser (fast, on-device, zero-dependency)
    if (durationMs == null || durationMs <= 0) {
      try {
        if (ext == '.wav') {
          durationMs = await _parseWavDuration(file);
        } else if (['.mp4', '.mov', '.m4a', '.m4v'].contains(ext)) {
          durationMs = await _parseMp4Duration(file);
        } else if (ext == '.mp3') {
          durationMs = await _parseMp3Duration(file, size);
        }
      } catch (_) {}
    }

    // 3. Fallback heuristic based on size
    if (durationMs == null || durationMs <= 0) {
      if (isAudioOnly) {
        // Assume ~128kbps audio (16000 bytes/sec)
        final sec = (size / 16000).round().clamp(5, 7200);
        durationMs = sec * 1000;
      } else {
        // Assume ~1.5 Mbps video (187500 bytes/sec)
        final sec = (size / 187500).round().clamp(5, 7200);
        durationMs = sec * 1000;
      }
    }

    return MediaMetadata(
      fileName: name,
      filePath: filePath,
      fileSizeBytes: size,
      durationMs: durationMs,
      hasVideo: !isAudioOnly,
    );
  }

  Future<int?> _parseWavDuration(File file) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final header = await raf.read(44);
      if (header.length < 44) return null;
      final byteData = ByteData.sublistView(header);
      final byteRate = byteData.getUint32(28, Endian.little);
      final fileSize = await file.length();
      final dataSize = fileSize > 44 ? fileSize - 44 : 0;
      if (byteRate > 0 && dataSize > 0) {
        return (dataSize * 1000) ~/ byteRate;
      }
    } finally {
      await raf.close();
    }
    return null;
  }

  Future<int?> _parseMp4Duration(File file) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final fileSize = await file.length();
      int pos = 0;
      // Read atom by atom looking for 'moov' -> 'mvhd'
      while (pos < fileSize && pos < 50 * 1024 * 1024) {
        await raf.setPosition(pos);
        final header = await raf.read(8);
        if (header.length < 8) break;
        final bd = ByteData.sublistView(header);
        int atomSize = bd.getUint32(0, Endian.big);
        final atomType = String.fromCharCodes(header.sublist(4, 8));

        if (atomSize == 1) {
          final extended = await raf.read(8);
          if (extended.length < 8) break;
          atomSize = ByteData.sublistView(extended).getUint64(0, Endian.big);
          pos += 8;
        }
        if (atomSize <= 0) break;

        if (atomType == 'moov') {
          // Inside moov, search for mvhd
          int moovPos = pos + 8;
          final moovEnd = pos + atomSize;
          while (moovPos < moovEnd) {
            await raf.setPosition(moovPos);
            final innerHdr = await raf.read(8);
            if (innerHdr.length < 8) break;
            final innerBd = ByteData.sublistView(innerHdr);
            final innerSize = innerBd.getUint32(0, Endian.big);
            final innerType = String.fromCharCodes(innerHdr.sublist(4, 8));
            if (innerType == 'mvhd') {
              final mvhdBytes = await raf.read(32);
              if (mvhdBytes.length >= 24) {
                final vbd = ByteData.sublistView(mvhdBytes);
                final version = vbd.getUint8(0);
                int timescale;
                int duration;
                if (version == 1 && mvhdBytes.length >= 32) {
                  timescale = vbd.getUint32(20, Endian.big);
                  duration = vbd.getUint64(24, Endian.big);
                } else {
                  timescale = vbd.getUint32(12, Endian.big);
                  duration = vbd.getUint32(16, Endian.big);
                }
                if (timescale > 0 && duration > 0) {
                  return ((duration * 1000) / timescale).round();
                }
              }
              break;
            }
            if (innerSize <= 0) break;
            moovPos += innerSize;
          }
          break;
        }
        pos += atomSize;
      }
    } finally {
      await raf.close();
    }
    return null;
  }

  Future<int?> _parseMp3Duration(File file, int fileSize) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final bytes = await raf.read(4096);
      int offset = 0;
      // Skip ID3v2 if present
      if (bytes.length >= 10 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
        final id3Size = (bytes[6] << 21) | (bytes[7] << 14) | (bytes[8] << 7) | bytes[9];
        offset = 10 + id3Size;
        if (offset < fileSize) {
          await raf.setPosition(offset);
          final frameBytes = await raf.read(1024);
          return _estimateMp3Duration(fileSize - offset, frameBytes);
        }
      }
      return _estimateMp3Duration(fileSize, bytes);
    } finally {
      await raf.close();
    }
  }

  int? _estimateMp3Duration(int audioBytes, List<int> bytes) {
    for (int i = 0; i < bytes.length - 4; i++) {
      if (bytes[i] == 0xFF && (bytes[i + 1] & 0xE0) == 0xE0) {
        // MPEG audio frame
        final bitrateIndex = (bytes[i + 2] >> 4) & 0x0F;
        const bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0];
        final bitrate = (bitrateIndex < bitrates.length ? bitrates[bitrateIndex] : 128) * 1000;
        if (bitrate > 0) {
          return ((audioBytes * 8 * 1000) / bitrate).round();
        }
      }
    }
    // Default ~128 kbps
    return ((audioBytes * 8 * 1000) / 128000).round();
  }
}
