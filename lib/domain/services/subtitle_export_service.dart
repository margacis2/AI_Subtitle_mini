import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/serializers/ass_serializer.dart';
import '../../data/serializers/srt_serializer.dart';
import '../../data/serializers/vtt_serializer.dart';
import '../../native/storage/android_storage_service.dart';
import '../entities/subtitle_cue.dart';
import '../entities/subtitle_style.dart';

class ExportResult {
  final String pathOrUri;
  final String fileName;
  final int cueCount;
  final String format;
  final bool isPublic;

  const ExportResult({
    required this.pathOrUri,
    required this.fileName,
    required this.cueCount,
    required this.format,
    required this.isPublic,
  });
}

class SubtitleExportService {
  SubtitleExportService._();

  /// Exports cues to the target format (.srt, .vtt, or .ass) using unified modern Android MediaStore / SAF storage.
  static Future<ExportResult> exportToFile({
    required String projectName,
    required List<SubtitleCue> cues,
    required String format, // 'srt', 'vtt', 'ass'
    SubtitleStyle style = const SubtitleStyle(),
    bool saveToPublicDownloads = true,
    String? customTreeUri,
  }) async {
    if (cues.isEmpty) {
      throw StateError('Cannot export empty subtitle list.');
    }

    final cleanFormat = format.toLowerCase().replaceAll('.', '');
    String content;

    switch (cleanFormat) {
      case 'vtt':
        content = VttSerializer.serialize(cues);
        break;
      case 'ass':
      case 'ssa':
        content = AssSerializer.serialize(cues, style: style);
        break;
      case 'srt':
      default:
        content = SrtSerializer.serialize(cues);
        break;
    }

    final safeName = projectName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final fileName = '$safeName.$cleanFormat';

    // 1. Custom Storage Access Framework (SAF) folder selected in Settings
    if (customTreeUri != null && customTreeUri.isNotEmpty) {
      final isValid = await AndroidStorageService.checkDirectoryAccess(customTreeUri);
      if (isValid) {
        final savedUri = await AndroidStorageService.saveToCustomDirectory(
          treeUri: customTreeUri,
          fileName: fileName,
          content: content,
          format: cleanFormat,
        );
        return ExportResult(
          pathOrUri: savedUri,
          fileName: fileName,
          cueCount: cues.length,
          format: cleanFormat.toUpperCase(),
          isPublic: true,
        );
      }
    }

    // 2. Default Public Downloads: Download/AI Subtitles/ (MediaStore on Android 10+)
    if (saveToPublicDownloads) {
      final publicPath = await AndroidStorageService.saveToPublicDownloads(
        fileName: fileName,
        content: content,
        format: cleanFormat,
      );
      return ExportResult(
        pathOrUri: publicPath,
        fileName: fileName,
        cueCount: cues.length,
        format: cleanFormat.toUpperCase(),
        isPublic: true,
      );
    }

    // 3. Fallback to private app documents directory
    final appDir = await getApplicationDocumentsDirectory();
    final targetFile = File(p.join(appDir.path, fileName));
    await targetFile.writeAsString(content, flush: true);
    return ExportResult(
      pathOrUri: targetFile.path,
      fileName: fileName,
      cueCount: cues.length,
      format: cleanFormat.toUpperCase(),
      isPublic: false,
    );
  }
}
