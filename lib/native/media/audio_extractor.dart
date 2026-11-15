import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioExtractor {
  static final AudioExtractor _instance = AudioExtractor._internal();
  factory AudioExtractor() => _instance;
  AudioExtractor._internal();

  /// Extracts 16kHz 16-bit mono WAV audio required by Whisper speech engine.
  Future<File> extractAudio({
    required String inputPath,
    required void Function(double progress, String status) onProgress,
    String? outputDir,
    int? knownDurationMs,
  }) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw Exception('Media file not found at: $inputPath');
    }

    onProgress(0.1, 'Preparing audio extraction...');
    final targetDir = outputDir != null ? Directory(outputDir) : await getTemporaryDirectory();
    final outBaseName = p.basenameWithoutExtension(inputPath);
    final outputPath = p.join(targetDir.path, '${outBaseName}_16k.wav');
    final outputFile = File(outputPath);

    if (await outputFile.exists()) {
      try {
        await outputFile.delete();
      } catch (_) {}
    }

    onProgress(0.25, 'Extracting 16kHz 16-bit mono PCM track with FFmpeg...');

    // 1. Try embedded FFmpegKit (Android/iOS/supported desktop)
    try {
      final session = await FFmpegKit.execute(
        '-y -i "$inputPath" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$outputPath"',
      );
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode) && await outputFile.exists() && (await outputFile.length()) > 44) {
        onProgress(1.0, 'Audio extraction complete.');
        return outputFile;
      }
    } catch (_) {}

    // 2. Try desktop CLI ffmpeg if running on desktop workstation
    try {
      final result = await Process.run('ffmpeg', [
        '-y',
        '-i',
        inputPath,
        '-vn',
        '-acodec',
        'pcm_s16le',
        '-ar',
        '16000',
        '-ac',
        '1',
        outputPath,
      ]);

      if (result.exitCode == 0 && await outputFile.exists() && (await outputFile.length()) > 44) {
        onProgress(1.0, 'Audio extraction complete.');
        return outputFile;
      }
    } catch (_) {}

    // 3. If input is already a WAV file, copy it directly
    if (inputPath.toLowerCase().endsWith('.wav')) {
      final copied = await inputFile.copy(outputPath);
      onProgress(1.0, 'Using source WAV track directly.');
      return copied;
    }

    throw Exception(
      'Failed to extract 16kHz audio track from $inputPath. Please verify the media file contains a valid audio stream.',
    );
  }
}
