import 'dart:convert';
import 'dart:io';

class UnigramTokenizer {
  final Map<String, int> vocab = {};
  final Map<int, String> idToVocab = {};

  UnigramTokenizer._();

  static Future<UnigramTokenizer> fromFile(String tokenizerJsonPath) async {
    final tokenizer = UnigramTokenizer._();
    final file = File(tokenizerJsonPath);
    if (!await file.exists()) {
      return tokenizer;
    }

    try {
      final jsonMap = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final model = jsonMap['model'] as Map<String, dynamic>?;
      if (model != null && model['vocab'] is List) {
        final list = model['vocab'] as List;
        for (int i = 0; i < list.length; i++) {
          final item = list[i];
          if (item is List && item.isNotEmpty) {
            final token = item[0] as String;
            tokenizer.vocab[token] = i;
            tokenizer.idToVocab[i] = token;
          }
        }
      }
    } catch (_) {}

    return tokenizer;
  }

  List<int> encode(String text) {
    // Simple subword tokenization
    final tokens = <int>[];
    final words = text.split(' ');
    for (final w in words) {
      final sub = ' $w';
      if (vocab.containsKey(sub)) {
        tokens.add(vocab[sub]!);
      } else if (vocab.containsKey(w)) {
        tokens.add(vocab[w]!);
      }
    }
    return tokens;
  }

  String decode(List<int> ids) {
    final buffer = StringBuffer();
    for (final id in ids) {
      final token = idToVocab[id];
      if (token != null) {
        if (token.startsWith(' ')) {
          buffer.write(' ');
          buffer.write(token.substring(1));
        } else {
          buffer.write(token);
        }
      }
    }
    return buffer.toString().trim();
  }
}
