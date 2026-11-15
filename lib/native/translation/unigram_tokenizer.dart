import 'dart:convert';
import 'dart:io';

class UnigramTokenizer {
  final Map<String, int> vocab = {};
  final Map<int, String> idToVocab = {};
  int padTokenId = 0;
  int eosTokenId = 1;
  int unkTokenId = 2;

  UnigramTokenizer._();

  static Future<UnigramTokenizer> fromFile(String tokenizerJsonPath) async {
    final tokenizer = UnigramTokenizer._();
    final file = File(tokenizerJsonPath);
    if (!await file.exists()) {
      return tokenizer;
    }

    try {
      final jsonMap = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      // 1. Parse Vocab from Model
      final model = jsonMap['model'] as Map<String, dynamic>?;
      if (model != null) {
        if (model['vocab'] is List) {
          final list = model['vocab'] as List;
          for (int i = 0; i < list.length; i++) {
            final item = list[i];
            if (item is List && item.isNotEmpty) {
              final token = item[0] as String;
              tokenizer.vocab[token] = i;
              tokenizer.idToVocab[i] = token;
            }
          }
        } else if (model['vocab'] is Map) {
          final map = model['vocab'] as Map<String, dynamic>;
          for (final entry in map.entries) {
            final id = (entry.value as num).toInt();
            tokenizer.vocab[entry.key] = id;
            tokenizer.idToVocab[id] = entry.key;
          }
        }
      }

      // 2. Parse Added / Special Tokens
      if (jsonMap['added_tokens'] is List) {
        for (final item in jsonMap['added_tokens'] as List) {
          if (item is Map) {
            final content = item['content'] as String?;
            final id = item['id'] as int?;
            if (content != null && id != null) {
              tokenizer.vocab[content] = id;
              tokenizer.idToVocab[id] = content;
              if (content == '</s>' || content == '<eos>') tokenizer.eosTokenId = id;
              if (content == '<pad>') tokenizer.padTokenId = id;
              if (content == '<unk>') tokenizer.unkTokenId = id;
            }
          }
        }
      }
    } catch (_) {}

    return tokenizer;
  }

  List<int> encode(String text) {
    if (vocab.isEmpty) return [];
    final tokens = <int>[];
    final words = text.trim().split(RegExp(r'\s+'));
    for (final w in words) {
      final sub = ' $w';
      if (vocab.containsKey(sub)) {
        tokens.add(vocab[sub]!);
      } else if (vocab.containsKey(w)) {
        tokens.add(vocab[w]!);
      } else {
        // Fallback character-level subword breakdown
        for (int i = 0; i < w.length; i++) {
          final ch = w[i];
          if (vocab.containsKey(ch)) {
            tokens.add(vocab[ch]!);
          } else {
            tokens.add(unkTokenId);
          }
        }
      }
    }
    tokens.add(eosTokenId);
    return tokens;
  }

  String decode(List<int> ids) {
    final buffer = StringBuffer();
    for (final id in ids) {
      if (id == padTokenId || id == eosTokenId) continue;
      final token = idToVocab[id];
      if (token != null) {
        if ((token.startsWith('<') && token.endsWith('>')) || token == '<s>' || token == '</s>') {
          continue;
        }
        if (token.startsWith(' ')) {
          buffer.write(' ');
          buffer.write(token.substring(1));
        } else if (token.startsWith('##')) {
          buffer.write(token.substring(2));
        } else {
          buffer.write(token);
        }
      }
    }
    return buffer.toString().trim();
  }
}
