import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AndroidStorageService {
  static const MethodChannel _channel = MethodChannel('com.aisubtitle.ai_sub_mini/storage');

  static String getMimeType(String format) {
    switch (format.toLowerCase().replaceAll('.', '')) {
      case 'vtt':
        return 'text/vtt';
      case 'ass':
      case 'ssa':
        return 'text/x-ssa';
      case 'srt':
      default:
        return 'application/x-subrip';
    }
  }

  /// Saves a subtitle file to public Downloads (MediaStore on Android 10+, public folder on legacy/desktop).
  static Future<String> saveToPublicDownloads({
    required String fileName,
    required String content,
    required String format,
  }) async {
    final mimeType = getMimeType(format);

    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('saveToPublicDownloads', {
          'fileName': fileName,
          'content': content,
          'mimeType': mimeType,
        });
        if (result != null && result.isNotEmpty) {
          return result;
        }
      } catch (e) {
        // Fallback to manual directory handling
      }
    }

    // Desktop & fallback
    Directory baseDir;
    try {
      final dl = await getDownloadsDirectory();
      baseDir = dl ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final targetDir = Directory(p.join(baseDir.path, 'AI Subtitles'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final targetFile = File(p.join(targetDir.path, fileName));
    await targetFile.writeAsString(content, flush: true);
    return targetFile.path;
  }

  /// Opens Android SAF system folder picker and returns selected Directory details.
  static Future<Map<String, String>?> pickDirectory() async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _channel.invokeMapMethod<String, String>('pickDirectory');
      return res;
    } catch (e) {
      return null;
    }
  }

  /// Saves to user-selected Storage Access Framework (SAF) folder.
  static Future<String> saveToCustomDirectory({
    required String treeUri,
    required String fileName,
    required String content,
    required String format,
  }) async {
    final mimeType = getMimeType(format);
    if (Platform.isAndroid) {
      final res = await _channel.invokeMethod<String>('saveToCustomDirectory', {
        'treeUri': treeUri,
        'fileName': fileName,
        'content': content,
        'mimeType': mimeType,
      });
      if (res != null) return res;
    }

    return await saveToPublicDownloads(
      fileName: fileName,
      content: content,
      format: format,
    );
  }

  /// Verifies if a previously saved SAF tree URI is still valid and writable.
  static Future<bool> checkDirectoryAccess(String treeUri) async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('checkDirectoryAccess', {
        'treeUri': treeUri,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
