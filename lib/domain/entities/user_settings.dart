import 'package:flutter/material.dart';

enum CensorMaskType {
  none,
  partial,
  full,
  placeholder;

  String get displayName {
    switch (this) {
      case CensorMaskType.none:
        return 'Preserve authentic spoken dialogue without automatic masking (Default: ON)';
      case CensorMaskType.partial:
        return 'Partially mask word (f**k)';
      case CensorMaskType.full:
        return 'Full asterisk masking (****)';
      case CensorMaskType.placeholder:
        return 'Placeholder ([censored])';
    }
  }
}

class UserSettings {
  final ThemeMode themeMode;
  final String defaultExportFormat;
  final CensorMaskType censorMaskType;
  final String censorPlaceholder;
  final String selectedModelId;
  final int threadCount;
  final bool exportToPublicDownloads;

  const UserSettings({
    this.themeMode = ThemeMode.dark,
    this.defaultExportFormat = 'srt',
    this.censorMaskType = CensorMaskType.none,
    this.censorPlaceholder = '[censored]',
    this.selectedModelId = 'base',
    this.threadCount = 4,
    this.exportToPublicDownloads = true,
  });

  UserSettings copyWith({
    ThemeMode? themeMode,
    String? defaultExportFormat,
    CensorMaskType? censorMaskType,
    String? censorPlaceholder,
    String? selectedModelId,
    int? threadCount,
    bool? exportToPublicDownloads,
  }) {
    return UserSettings(
      themeMode: themeMode ?? this.themeMode,
      defaultExportFormat: defaultExportFormat ?? this.defaultExportFormat,
      censorMaskType: censorMaskType ?? this.censorMaskType,
      censorPlaceholder: censorPlaceholder ?? this.censorPlaceholder,
      selectedModelId: selectedModelId ?? this.selectedModelId,
      threadCount: threadCount ?? this.threadCount,
      exportToPublicDownloads: exportToPublicDownloads ?? this.exportToPublicDownloads,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'themeMode': themeMode.name,
      'defaultExportFormat': defaultExportFormat,
      'censorMaskType': censorMaskType.name,
      'censorPlaceholder': censorPlaceholder,
      'selectedModelId': selectedModelId,
      'threadCount': threadCount,
      'exportToPublicDownloads': exportToPublicDownloads ? 1 : 0,
    };
  }

  factory UserSettings.fromMap(Map<String, dynamic> map) {
    ThemeMode parseTheme(String? v) {
      if (v == 'light') return ThemeMode.light;
      if (v == 'system') return ThemeMode.system;
      return ThemeMode.dark;
    }

    CensorMaskType parseMask(String? v) {
      return CensorMaskType.values.firstWhere(
        (e) => e.name == v,
        orElse: () => CensorMaskType.none,
      );
    }

    return UserSettings(
      themeMode: parseTheme(map['themeMode']),
      defaultExportFormat: map['defaultExportFormat'] ?? 'srt',
      censorMaskType: parseMask(map['censorMaskType']),
      censorPlaceholder: map['censorPlaceholder'] ?? '[censored]',
      selectedModelId: map['selectedModelId'] ?? 'base',
      threadCount: map['threadCount'] ?? 4,
      exportToPublicDownloads: map['exportToPublicDownloads'] == 1 || map['exportToPublicDownloads'] == true,
    );
  }
}
