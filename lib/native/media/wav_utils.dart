import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

class WavChunk {
  final int chunkIndex; // 1-based
  final int totalChunks;
  final int startMs;
  final int endMs;
  final String path;

  const WavChunk({
    required this.chunkIndex,
    required this.totalChunks,
    required this.startMs,
    required this.endMs,
    required this.path,
  });

  String get timeRangeLabel {
    final startSec = (startMs / 1000).floor();
    final endSec = (endMs / 1000).ceil();
    final sMin = (startSec ~/ 60).toString().padLeft(2, '0');
    final sSec = (startSec % 60).toString().padLeft(2, '0');
    final eMin = (endSec ~/ 60).toString().padLeft(2, '0');
    final eSec = (endSec % 60).toString().padLeft(2, '0');
    return '$sMin:$sSec - $eMin:$eSec';
  }
}

class WavUtils {
  static const int sampleRate = 16000;
  static const int bytesPerSample = 2; // 16-bit
  static const int channels = 1; // mono
  static const int bytesPerSecond = sampleRate * bytesPerSample * channels; // 32000 bytes/sec

  /// Returns audio duration in milliseconds from a 16kHz mono 16-bit PCM WAV file.
  static int getDurationMs(File wavFile) {
    if (!wavFile.existsSync()) return 0;
    final length = wavFile.lengthSync();
    if (length <= 44) return 0;
    final dataBytes = length - 44;
    return ((dataBytes / bytesPerSecond) * 1000).round();
  }

  /// Formats seconds or milliseconds into mm:ss or hh:mm:ss.
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Slices a 16kHz mono WAV file from [startMs] to [endMs].
  static Future<File> sliceWav({
    required File sourceWav,
    required int startMs,
    required int endMs,
    required String outputPath,
  }) async {
    final startByte = 44 + ((startMs / 1000.0) * bytesPerSecond).round();
    final endByte = 44 + ((endMs / 1000.0) * bytesPerSecond).round();

    final fileLength = await sourceWav.length();
    final clampedStart = startByte.clamp(44, fileLength);
    final clampedEnd = endByte.clamp(clampedStart, fileLength);
    final pcmBytesLength = clampedEnd - clampedStart;

    final header = ByteData(44);
    header.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    header.setUint32(4, 36 + pcmBytesLength, Endian.little);
    header.setUint32(8, 0x57415645, Endian.big); // "WAVE"
    header.setUint32(12, 0x666D7420, Endian.big); // "fmt "
    header.setUint32(16, 16, Endian.little); // subchunk1 size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // audio format (1 = PCM)
    header.setUint16(22, 1, Endian.little); // num channels (1 = mono)
    header.setUint32(24, 16000, Endian.little); // sample rate (16000)
    header.setUint32(28, 32000, Endian.little); // byte rate (16000 * 1 * 2)
    header.setUint16(32, 2, Endian.little); // block align (1 * 2)
    header.setUint16(34, 16, Endian.little); // bits per sample (16)
    header.setUint32(36, 0x64617461, Endian.big); // "data"
    header.setUint32(40, pcmBytesLength, Endian.little);

    final outFile = File(outputPath);
    final outDir = outFile.parent;
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final raf = await outFile.open(mode: FileMode.write);
    await raf.writeFrom(header.buffer.asUint8List());

    final srcRaf = await sourceWav.open(mode: FileMode.read);
    await srcRaf.setPosition(clampedStart);

    int remaining = pcmBytesLength;
    const bufferSize = 64 * 1024;
    while (remaining > 0) {
      final toRead = remaining > bufferSize ? bufferSize : remaining;
      final chunkData = await srcRaf.read(toRead);
      if (chunkData.isEmpty) break;
      await raf.writeFrom(chunkData);
      remaining -= chunkData.length;
    }

    await srcRaf.close();
    await raf.close();

    return outFile;
  }

  /// Computes the total number of chunks for a given audio file duration.
  static int calculateChunkCount(int totalDurationMs, {int chunkDurationMs = 30000}) {
    if (totalDurationMs <= 0) return 0;
    if (totalDurationMs <= 45000) return 1;
    return ((totalDurationMs + chunkDurationMs - 1) ~/ chunkDurationMs);
  }

  /// Calculates start and end timestamps (in milliseconds) for chunk at [index] (0-based).
  static (int startMs, int endMs) getChunkRange(int index, int totalDurationMs, {int chunkDurationMs = 30000}) {
    if (totalDurationMs <= 45000) return (0, totalDurationMs);
    final startMs = index * chunkDurationMs;
    final endMs = ((index + 1) * chunkDurationMs).clamp(0, totalDurationMs);
    return (startMs, endMs);
  }

  /// Splits an audio file into 30-second sequential chunks for Whisper processing.
  static Future<List<WavChunk>> createChunks({
    required File sourceWav,
    required String tempDirectoryPath,
    int chunkDurationMs = 30000,
  }) async {
    final totalDurationMs = getDurationMs(sourceWav);
    if (totalDurationMs <= 0) {
      return [];
    }

    // If audio is shorter than 45 seconds, process as a single chunk directly
    if (totalDurationMs <= 45000) {
      return [
        WavChunk(
          chunkIndex: 1,
          totalChunks: 1,
          startMs: 0,
          endMs: totalDurationMs,
          path: sourceWav.path,
        ),
      ];
    }

    final List<WavChunk> chunks = [];
    final totalChunks = ((totalDurationMs + chunkDurationMs - 1) ~/ chunkDurationMs);

    for (int i = 0; i < totalChunks; i++) {
      final startMs = i * chunkDurationMs;
      final endMs = ((i + 1) * chunkDurationMs).clamp(0, totalDurationMs);
      final chunkFileName = 'chunk_${i + 1}_of_$totalChunks.wav';
      final chunkPath = p.join(tempDirectoryPath, chunkFileName);

      final chunkFile = await sliceWav(
        sourceWav: sourceWav,
        startMs: startMs,
        endMs: endMs,
        outputPath: chunkPath,
      );

      chunks.add(WavChunk(
        chunkIndex: i + 1,
        totalChunks: totalChunks,
        startMs: startMs,
        endMs: endMs,
        path: chunkFile.path,
      ));
    }

    return chunks;
  }
}
