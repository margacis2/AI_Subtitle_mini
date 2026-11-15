import 'dart:convert';
import 'dart:io';
import 'dart:math';

class UnigramTokenizer {
  final Map<String, int> vocab = {};
  final Map<int, String> idToVocab = {};
  int padTokenId = 60715;
  int eosTokenId = 0;
  int unkTokenId = 1;
  int maxTokenLength = 1;

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
              String token = item[0] as String;
              if (token.startsWith(' ') && !token.startsWith('\u2581')) {
                token = '\u2581${token.substring(1)}';
              }
              tokenizer.vocab[token] = i;
              tokenizer.idToVocab[i] = token;
              if (token.length > tokenizer.maxTokenLength) {
                tokenizer.maxTokenLength = token.length;
              }
            }
          }
        } else if (model['vocab'] is Map) {
          final map = model['vocab'] as Map<String, dynamic>;
          for (final entry in map.entries) {
            final id = (entry.value as num).toInt();
            String token = entry.key;
            if (token.startsWith(' ') && !token.startsWith('\u2581')) {
              token = '\u2581${token.substring(1)}';
            }
            tokenizer.vocab[token] = id;
            tokenizer.idToVocab[id] = token;
            if (token.length > tokenizer.maxTokenLength) {
              tokenizer.maxTokenLength = token.length;
            }
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

      // If pad token wasn't in added_tokens, check if in vocab
      if (tokenizer.vocab.containsKey('<pad>')) {
        tokenizer.padTokenId = tokenizer.vocab['<pad>']!;
      }
      if (tokenizer.vocab.containsKey('</s>')) {
        tokenizer.eosTokenId = tokenizer.vocab['</s>']!;
      }
      if (tokenizer.vocab.containsKey('<unk>')) {
        tokenizer.unkTokenId = tokenizer.vocab['<unk>']!;
      }
    } catch (_) {}

    return tokenizer;
  }

  /// Encodes text into subword token IDs using greedy longest-match SentencePiece Unigram tokenization.
  List<int> encode(String text) {
    final clean = text.trim();
    if (clean.isEmpty || vocab.isEmpty) return [];

    // Prepend SentencePiece metaspace \u2581 and normalize spaces
    String prepared = clean.replaceAll(' ', '\u2581');
    if (!prepared.startsWith('\u2581')) {
      prepared = '\u2581$prepared';
    }

    final tokens = <int>[];
    int i = 0;
    final length = prepared.length;

    while (i < length) {
      bool matched = false;
      final limit = min(maxTokenLength, length - i);

      for (int len = limit; len > 0; len--) {
        final sub = prepared.substring(i, i + len);
        final id = vocab[sub];
        if (id != null) {
          tokens.add(id);
          i += len;
          matched = true;
          break;
        }
      }

      if (!matched) {
        // Fallback: emit unk for single unrecognized character
        tokens.add(unkTokenId);
        i += 1;
      }
    }

    tokens.add(eosTokenId);
    return tokens;
  }

  /// Decodes a sequence of subword token IDs into readable target text.
  String decode(List<int> ids) {
    final buffer = StringBuffer();
    for (final id in ids) {
      if (id == padTokenId || id == eosTokenId) continue;
      final token = idToVocab[id];
      if (token == null) continue;

      if ((token.startsWith('<') && token.endsWith('>')) || token == '<s>' || token == '</s>') {
        continue;
      }

      if (token.startsWith('\u2581')) {
        buffer.write(' ');
        buffer.write(token.substring(1));
      } else if (token.startsWith(' ')) {
        buffer.write(' ');
        buffer.write(token.substring(1));
      } else if (token.startsWith('##')) {
        buffer.write(token.substring(2));
      } else {
        buffer.write(token);
      }
    }
    return buffer.toString().trim();
  }
}
