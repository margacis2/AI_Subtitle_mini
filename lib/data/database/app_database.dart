import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../domain/entities/project.dart';
import '../../domain/entities/subtitle_cue.dart';
import '../../domain/entities/processing_job.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'ai_subtitle_studio.db');

    return await openDatabase(
      dbPath,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute("ALTER TABLE projects ADD COLUMN selected_model TEXT DEFAULT 'base'");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE processing_jobs ADD COLUMN selected_model TEXT DEFAULT 'base'");
          } catch (_) {}
        }
        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE processing_jobs ADD COLUMN elapsed_seconds INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE processing_jobs ADD COLUMN eta_seconds INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE processing_jobs ADD COLUMN audio_duration_seconds INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE processing_jobs ADD COLUMN current_chunk INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE processing_jobs ADD COLUMN total_chunks INTEGER');
          } catch (_) {}
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            media_path TEXT,
            audio_path TEXT,
            subtitle_file_path TEXT,
            source_language TEXT NOT NULL,
            target_language TEXT,
            cue_count INTEGER NOT NULL DEFAULT 0,
            duration_ms INTEGER,
            selected_model TEXT DEFAULT 'base',
            status TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE subtitle_cues (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id TEXT NOT NULL,
            cue_index INTEGER NOT NULL,
            start_ms INTEGER NOT NULL,
            end_ms INTEGER NOT NULL,
            text TEXT NOT NULL,
            original_text TEXT,
            speaker TEXT,
            custom_style TEXT,
            FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE model_installations (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            file_name TEXT NOT NULL,
            local_path TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            sha256 TEXT,
            installed_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE processing_jobs (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            title TEXT NOT NULL,
            stage TEXT NOT NULL,
            progress REAL NOT NULL DEFAULT 0.0,
            current_step TEXT,
            error_details TEXT,
            created_at TEXT NOT NULL,
            completed_at TEXT,
            retry_count INTEGER NOT NULL DEFAULT 0,
            input_path TEXT,
            output_path TEXT,
            settings TEXT,
            selected_model TEXT DEFAULT 'base',
            elapsed_seconds INTEGER,
            eta_seconds INTEGER,
            audio_duration_seconds INTEGER,
            current_chunk INTEGER,
            total_chunks INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE language_pack_installations (
            id TEXT PRIMARY KEY,
            source_lang TEXT NOT NULL,
            target_lang TEXT NOT NULL,
            display_name TEXT NOT NULL,
            local_path TEXT NOT NULL,
            installed_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // --- PROJECTS ---
  Future<List<Project>> getAllProjects() async {
    final db = await database;
    final maps = await db.query('projects', orderBy: 'updated_at DESC');
    return maps.map((m) => Project.fromMap(m)).toList();
  }

  Future<Project?> getProject(String id) async {
    final db = await database;
    final maps = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Project.fromMap(maps.first);
  }

  Future<void> saveProject(Project project) async {
    final db = await database;
    await db.insert(
      'projects',
      project.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProject(String id) async {
    final db = await database;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // --- SUBTITLE CUES ---
  Future<List<SubtitleCue>> getCuesForProject(String projectId) async {
    final db = await database;
    final maps = await db.query(
      'subtitle_cues',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'cue_index ASC, start_ms ASC',
    );
    return maps.map((m) => SubtitleCue.fromMap(m)).toList();
  }

  Future<void> replaceCuesForProject(String projectId, List<SubtitleCue> cues) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('subtitle_cues', where: 'project_id = ?', whereArgs: [projectId]);
      for (int i = 0; i < cues.length; i++) {
        final cue = cues[i].copyWith(cueIndex: i + 1, projectId: projectId);
        await txn.insert('subtitle_cues', cue.toMap());
      }
      await txn.update(
        'projects',
        {
          'cue_count': cues.length,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [projectId],
      );
    });
  }

  Future<int> insertCue(SubtitleCue cue) async {
    final db = await database;
    return await db.insert('subtitle_cues', cue.toMap());
  }

  Future<void> updateCue(SubtitleCue cue) async {
    final db = await database;
    await db.update(
      'subtitle_cues',
      cue.toMap(),
      where: 'id = ?',
      whereArgs: [cue.id],
    );
  }

  Future<void> deleteCue(int id) async {
    final db = await database;
    await db.delete('subtitle_cues', where: 'id = ?', whereArgs: [id]);
  }

  // --- PROCESSING JOBS ---
  Future<List<ProcessingJob>> getAllJobs() async {
    final db = await database;
    final maps = await db.query('processing_jobs', orderBy: 'created_at DESC');
    return maps.map((m) => ProcessingJob.fromMap(m)).toList();
  }

  Future<ProcessingJob?> getJob(String id) async {
    final db = await database;
    final maps = await db.query('processing_jobs', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return ProcessingJob.fromMap(maps.first);
  }

  Future<void> saveJob(ProcessingJob job) async {
    final db = await database;
    await db.insert(
      'processing_jobs',
      job.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteJob(String id) async {
    final db = await database;
    await db.delete('processing_jobs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearCompletedJobs() async {
    final db = await database;
    await db.delete(
      'processing_jobs',
      where: 'stage IN (?, ?, ?)',
      whereArgs: ['completed', 'failed', 'cancelled'],
    );
  }

  // --- MODEL INSTALLATIONS ---
  Future<List<Map<String, dynamic>>> getInstalledModels() async {
    final db = await database;
    return await db.query('model_installations');
  }

  Future<void> recordModelInstallation({
    required String id,
    required String displayName,
    required String fileName,
    required String localPath,
    required int sizeBytes,
    String? sha256,
  }) async {
    final db = await database;
    await db.insert(
      'model_installations',
      {
        'id': id,
        'display_name': displayName,
        'file_name': fileName,
        'local_path': localPath,
        'size_bytes': sizeBytes,
        'sha256': sha256,
        'installed_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeModelInstallation(String id) async {
    final db = await database;
    await db.delete('model_installations', where: 'id = ?', whereArgs: [id]);
  }

  // --- LANGUAGE PACK INSTALLATIONS ---
  Future<List<Map<String, dynamic>>> getInstalledLanguagePacks() async {
    final db = await database;
    return await db.query('language_pack_installations');
  }

  Future<void> recordLanguagePackInstallation({
    required String id,
    required String sourceLang,
    required String targetLang,
    required String displayName,
    required String localPath,
  }) async {
    final db = await database;
    await db.insert(
      'language_pack_installations',
      {
        'id': id,
        'source_lang': sourceLang,
        'target_lang': targetLang,
        'display_name': displayName,
        'local_path': localPath,
        'installed_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeLanguagePackInstallation(String id) async {
    final db = await database;
    await db.delete('language_pack_installations', where: 'id = ?', whereArgs: [id]);
  }
}
