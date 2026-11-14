import 'package:equatable/equatable.dart';

class SubtitleCue extends Equatable {
  final int? id;
  final String projectId;
  final int cueIndex;
  final int startMs;
  final int endMs;
  final String text;
  final String? originalText;
  final String? speaker;
  final String? customStyle;

  const SubtitleCue({
    this.id,
    required this.projectId,
    required this.cueIndex,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.originalText,
    this.speaker,
    this.customStyle,
  });

  int get durationMs => (endMs - startMs).clamp(0, 86400000);

  SubtitleCue copyWith({
    int? id,
    String? projectId,
    int? cueIndex,
    int? startMs,
    int? endMs,
    String? text,
    String? originalText,
    String? speaker,
    String? customStyle,
  }) {
    return SubtitleCue(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      cueIndex: cueIndex ?? this.cueIndex,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      text: text ?? this.text,
      originalText: originalText ?? this.originalText,
      speaker: speaker ?? this.speaker,
      customStyle: customStyle ?? this.customStyle,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'project_id': projectId,
      'cue_index': cueIndex,
      'start_ms': startMs,
      'end_ms': endMs,
      'text': text,
      'original_text': originalText,
      'speaker': speaker,
      'custom_style': customStyle,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory SubtitleCue.fromMap(Map<String, dynamic> map) {
    return SubtitleCue(
      id: map['id'] as int?,
      projectId: map['project_id'] as String? ?? '',
      cueIndex: map['cue_index'] as int? ?? 0,
      startMs: map['start_ms'] as int? ?? 0,
      endMs: map['end_ms'] as int? ?? 0,
      text: map['text'] as String? ?? '',
      originalText: map['original_text'] as String?,
      speaker: map['speaker'] as String?,
      customStyle: map['custom_style'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        projectId,
        cueIndex,
        startMs,
        endMs,
        text,
        originalText,
        speaker,
        customStyle,
      ];
}
