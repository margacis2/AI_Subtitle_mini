import 'dart:convert';
import 'package:flutter/material.dart';

enum SubtitleAlignment {
  bottomCenter,
  bottomLeft,
  bottomRight,
  topCenter;

  String get displayName {
    switch (this) {
      case SubtitleAlignment.bottomCenter:
        return 'Bottom Center (Standard)';
      case SubtitleAlignment.bottomLeft:
        return 'Bottom Left';
      case SubtitleAlignment.bottomRight:
        return 'Bottom Right';
      case SubtitleAlignment.topCenter:
        return 'Top Center';
    }
  }

  TextAlign get textAlign {
    switch (this) {
      case SubtitleAlignment.bottomLeft:
        return TextAlign.left;
      case SubtitleAlignment.bottomRight:
        return TextAlign.right;
      case SubtitleAlignment.bottomCenter:
      case SubtitleAlignment.topCenter:
        return TextAlign.center;
    }
  }

  Alignment get alignment {
    switch (this) {
      case SubtitleAlignment.bottomCenter:
        return Alignment.bottomCenter;
      case SubtitleAlignment.bottomLeft:
        return Alignment.bottomLeft;
      case SubtitleAlignment.bottomRight:
        return Alignment.bottomRight;
      case SubtitleAlignment.topCenter:
        return Alignment.topCenter;
    }
  }
}

class SubtitleStyle {
  final double fontSize;
  final Color textColor;
  final Color backgroundColor;
  final Color outlineColor;
  final double outlineWidth;
  final String fontFamily;
  final SubtitleAlignment alignment;
  final bool isBold;
  final bool isItalic;

  const SubtitleStyle({
    this.fontSize = 20.0,
    this.textColor = Colors.white,
    this.backgroundColor = Colors.black54,
    this.outlineColor = Colors.black,
    this.outlineWidth = 1.5,
    this.fontFamily = 'Roboto',
    this.alignment = SubtitleAlignment.bottomCenter,
    this.isBold = true,
    this.isItalic = false,
  });

  SubtitleStyle copyWith({
    double? fontSize,
    Color? textColor,
    Color? backgroundColor,
    Color? outlineColor,
    double? outlineWidth,
    String? fontFamily,
    SubtitleAlignment? alignment,
    bool? isBold,
    bool? isItalic,
  }) {
    return SubtitleStyle(
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      outlineColor: outlineColor ?? this.outlineColor,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      fontFamily: fontFamily ?? this.fontFamily,
      alignment: alignment ?? this.alignment,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fontSize': fontSize,
      'textColor': textColor.toARGB32(),
      'backgroundColor': backgroundColor.toARGB32(),
      'outlineColor': outlineColor.toARGB32(),
      'outlineWidth': outlineWidth,
      'fontFamily': fontFamily,
      'alignment': alignment.name,
      'isBold': isBold ? 1 : 0,
      'isItalic': isItalic ? 1 : 0,
    };
  }

  String toJson() => jsonEncode(toMap());

  factory SubtitleStyle.fromMap(Map<String, dynamic> map) {
    SubtitleAlignment parseAlign(String? s) {
      return SubtitleAlignment.values.firstWhere(
        (e) => e.name == s,
        orElse: () => SubtitleAlignment.bottomCenter,
      );
    }

    return SubtitleStyle(
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 20.0,
      textColor: map['textColor'] != null ? Color(map['textColor'] as int) : Colors.white,
      backgroundColor: map['backgroundColor'] != null ? Color(map['backgroundColor'] as int) : Colors.black54,
      outlineColor: map['outlineColor'] != null ? Color(map['outlineColor'] as int) : Colors.black,
      outlineWidth: (map['outlineWidth'] as num?)?.toDouble() ?? 1.5,
      fontFamily: map['fontFamily'] ?? 'Roboto',
      alignment: parseAlign(map['alignment']),
      isBold: map['isBold'] == 1 || map['isBold'] == true,
      isItalic: map['isItalic'] == 1 || map['isItalic'] == true,
    );
  }

  factory SubtitleStyle.fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SubtitleStyle.fromMap(map);
    } catch (_) {
      return const SubtitleStyle();
    }
  }
}
