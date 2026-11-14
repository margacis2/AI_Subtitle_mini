import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/database/app_database.dart';
import '../entities/translation_pack_info.dart';

class TranslationPackManager {
  final AppDatabase _db = AppDatabase();
  final Dio _dio = Dio();

  Future<List<TranslationPackInfo>> getPacksWithStatus() async {
    final installed = await _db.getInstalledLanguagePacks();
    final installedMap = {for (var i in installed) i['id'] as String: i['local_path'] as String};

    return TranslationPackInfo.catalog.map((info) {
      final localPath = installedMap[info.id];
      final isInst = localPath != null && Directory(localPath).existsSync();
      return info.copyWith(
        isInstalled: isInst,
        localPath: localPath,
      );
    }).toList();
  }

  Future<void> downloadPack({
    required TranslationPackInfo pack,
    required void Function(double progress, String status) onProgress,
    CancelToken? cancelToken,
  }) async {
    final appDir = await getApplicationSupportDirectory();
    final packDir = Directory(p.join(appDir.path, 'translation_packs', pack.id));
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }

    final encoderPath = p.join(packDir.path, 'encoder_model_quantized.onnx');
    final decoderPath = p.join(packDir.path, 'decoder_model_quantized.onnx');
    final tokenizerPath = p.join(packDir.path, 'tokenizer.json');

    // 1. Download Tokenizer
    onProgress(0.05, 'Downloading Tokenizer vocabulary...');
    await _dio.download(
      pack.tokenizerUrl,
      tokenizerPath,
      cancelToken: cancelToken,
    );

    // 2. Download Encoder
    onProgress(0.15, 'Downloading ONNX Encoder model...');
    await _dio.download(
      pack.encoderUrl,
      encoderPath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final frac = (received / total) * 0.4;
          onProgress(0.15 + frac, 'Downloading Encoder (${(frac * 100).toStringAsFixed(0)}%)...');
        }
      },
    );

    // 3. Download Decoder
    onProgress(0.55, 'Downloading ONNX Decoder model...');
    await _dio.download(
      pack.decoderUrl,
      decoderPath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final frac = (received / total) * 0.4;
          onProgress(0.55 + frac, 'Downloading Decoder (${(frac * 100).toStringAsFixed(0)}%)...');
        }
      },
    );

    // 4. Save to database
    await _db.recordLanguagePackInstallation(
      id: pack.id,
      sourceLang: pack.sourceLang,
      targetLang: pack.targetLang,
      displayName: pack.displayName,
      localPath: packDir.path,
    );

    onProgress(1.0, 'Installation complete!');
  }

  Future<void> uninstallPack(String packId) async {
    final appDir = await getApplicationSupportDirectory();
    final packDir = Directory(p.join(appDir.path, 'translation_packs', packId));
    if (await packDir.exists()) {
      await packDir.delete(recursive: true);
    }
    await _db.removeLanguagePackInstallation(packId);
  }
}
