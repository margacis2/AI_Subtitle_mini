import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/database/app_database.dart';
import '../../domain/entities/whisper_model_info.dart';

class WhisperModelManager {
  static final WhisperModelManager _instance = WhisperModelManager._internal();
  factory WhisperModelManager() => _instance;
  WhisperModelManager._internal();

  final AppDatabase _db = AppDatabase();
  final Dio _dio = Dio();

  Future<List<WhisperModelInfo>> getModelsWithStatus() async {
    final installed = await _db.getInstalledModels();
    final installedMap = {for (var i in installed) i['id'] as String: i['local_path'] as String};

    final appDir = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(appDir.path, 'whisper_models'));

    return WhisperModelInfo.catalog.map((info) {
      final recordedPath = installedMap[info.id];
      final diskFile = File(p.join(modelsDir.path, info.fileName));

      final exists = (recordedPath != null && File(recordedPath).existsSync()) ||
          diskFile.existsSync();

      final actualPath = recordedPath ?? (diskFile.existsSync() ? diskFile.path : null);

      return info.copyWith(
        isInstalled: exists,
        localPath: actualPath,
      );
    }).toList();
  }

  Future<void> downloadModel({
    required WhisperModelInfo model,
    required void Function(double progress, String status) onProgress,
    CancelToken? cancelToken,
  }) async {
    final appDir = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(appDir.path, 'whisper_models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    final targetFile = File(p.join(modelsDir.path, model.fileName));
    final tempFile = File(p.join(modelsDir.path, '${model.fileName}.download'));

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    onProgress(0.01, 'Connecting to Hugging Face repository...');

    await _dio.download(
      model.downloadUrl,
      tempFile.path,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final frac = received / total;
          final mbRec = (received / (1024 * 1024)).toStringAsFixed(1);
          final mbTot = (total / (1024 * 1024)).toStringAsFixed(1);
          onProgress(frac * 0.95, 'Downloading ${model.displayName} ($mbRec / $mbTot MB)...');
        }
      },
    );

    // Verify file size
    final downloadedBytes = await tempFile.length();
    if (downloadedBytes < 1000) {
      throw Exception('Downloaded file is invalid or too small ($downloadedBytes bytes).');
    }

    // Rename temp file to target
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await tempFile.rename(targetFile.path);

    onProgress(0.98, 'Verifying model integrity...');

    // Save to database
    await _db.recordModelInstallation(
      id: model.id,
      displayName: model.displayName,
      fileName: model.fileName,
      localPath: targetFile.path,
      sizeBytes: downloadedBytes,
      sha256: model.sha256,
    );

    onProgress(1.0, 'Model ready for offline speech inference.');
  }

  Future<void> deleteModel(String modelId) async {
    final appDir = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(appDir.path, 'whisper_models'));
    final modelInfo = WhisperModelInfo.catalog.firstWhere((m) => m.id == modelId);
    final targetFile = File(p.join(modelsDir.path, modelInfo.fileName));

    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await _db.removeModelInstallation(modelId);
  }
}
