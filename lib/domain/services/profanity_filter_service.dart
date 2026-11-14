import '../entities/user_settings.dart';
import '../entities/subtitle_cue.dart';

class ProfanityFilterService {
  static final Set<String> _profanityList = {
    'fuck', 'fucking', 'fucked', 'fucker', 'fuckers',
    'shit', 'shitty', 'bullshit',
    'bitch', 'bitches', 'bitching',
    'ass', 'asshole', 'assholes', 'badass',
    'bastard', 'bastards',
    'dick', 'dicks', 'dickhead',
    'cunt', 'cunts',
    'damn', 'dammit',
    'piss', 'pissed',
    'cock', 'cocks',
    'slut', 'sluts',
    'whore', 'whores',
  };

  /// Masks a single text string according to the selected policy.
  static String maskText(String text, CensorMaskType maskType, {String placeholder = '[censored]'}) {
    if (maskType == CensorMaskType.none || text.isEmpty) {
      return text;
    }

    final words = text.split(RegExp(r'(\s+|[.,!?;:"()\-])'));
    String result = text;

    for (final rawWord in words) {
      final cleanWord = rawWord.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (_profanityList.contains(cleanWord)) {
        final replacement = _getReplacement(rawWord, maskType, placeholder);
        // Replace whole word case-insensitively
        final regex = RegExp(r'\b' + RegExp.escape(rawWord) + r'\b', caseSensitive: false);
        result = result.replaceAll(regex, replacement);
      }
    }

    return result;
  }

  /// Masks a list of subtitle cues according to the policy.
  static List<SubtitleCue> maskCues(List<SubtitleCue> cues, CensorMaskType maskType, {String placeholder = '[censored]'}) {
    if (maskType == CensorMaskType.none) {
      return cues;
    }

    return cues.map((cue) {
      final filtered = maskText(cue.text, maskType, placeholder: placeholder);
      return cue.copyWith(
        text: filtered,
        originalText: cue.originalText ?? cue.text,
      );
    }).toList();
  }

  static String _getReplacement(String word, CensorMaskType maskType, String placeholder) {
    switch (maskType) {
      case CensorMaskType.none:
        return word;
      case CensorMaskType.partial:
        if (word.length <= 2) return '*' * word.length;
        return word[0] + ('*' * (word.length - 2)) + word[word.length - 1];
      case CensorMaskType.full:
        return '*' * word.length;
      case CensorMaskType.placeholder:
        return placeholder;
    }
  }
}
