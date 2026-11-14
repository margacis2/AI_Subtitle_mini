import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/serializers/ass_serializer.dart';
import '../../data/serializers/srt_serializer.dart';
import '../../data/serializers/vtt_serializer.dart';
import '../entities/subtitle_cue.dart';
import '../entities/subtitle_style.dart';

class SubtitleExportService {
  SubtitleExportService._();

  /// Exports cues to the target format (.srt, .vtt, or .ass).
  static Future<File> exportToFile({
    required String projectName,
    required List<SubtitleCue> cues,
    required String format, // 'srt', 'vtt', 'ass'
    SubtitleStyle style = const SubtitleStyle(),
    bool saveToPublicDownloads = true,
  }) async {
    final cleanFormat = format.toLowerCase().replaceAll('.', '');
    String content;

    switch (cleanFormat) {
      case 'vtt':
        content = VttSerializer.serialize(cues);
        break;
      case 'ass':
        content = AssSerializer.serialize(cues, style: style);
        break;
      case 'srt':
      default:
        content = SrtSerializer.serialize(cues);
        break;
    }

    // Determine destination folder
    Directory targetDir;
    if (saveToPublicDownloads) {
      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        // Try public Downloads/AI Subtitles
        final downloadsPath = '/storage/emulated/0/Download/AI Subtitles';
        final d = Directory(downloadsPath);
        if (await d.exists() || await _canCreateDir(d)) {
          targetDir = d;
        } else {
          targetDir = Directory(p.join(extDir?.path ?? '', 'AI Subtitles'))..createSync(recursive: true);
        }
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final dl = await getDownloadsDirectory();
        targetDir = Directory(p.join(dl?.path ?? '', 'AI Subtitles'))..createSync(recursive: true);
      } else {
        targetDir = await getApplicationDocumentsDirectory();
      }
    } else {
      targetDir = await getApplicationDocumentsDirectory();
    }

    final safeName = projectName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final filePath = p.join(targetDir.path, '$safeName.$cleanFormat');
    final file = File(filePath);
    await file.writeAsString(content, flush: true);
    return file;
  }

  static Future<bool> _canCreateDir(Directory d) async {
    try {
      await d.create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
