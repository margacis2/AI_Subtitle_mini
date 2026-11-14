import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../native/translation/onnx_translation_engine.dart';
import '../../providers.dart';

class TranslateScreen extends ConsumerStatefulWidget {
  const TranslateScreen({super.key});

  @override
  ConsumerState<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends ConsumerState<TranslateScreen> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();
  String _sourceLang = 'ja';
  String _targetLang = 'en';
  bool _isTranslating = false;

  final List<Map<String, String>> _langs = [
    {'code': 'ja', 'name': 'Japanese'},
    {'code': 'ko', 'name': 'Korean'},
    {'code': 'hi', 'name': 'Hindi'},
    {'code': 'ta', 'name': 'Tamil'},
    {'code': 'en', 'name': 'English'},
  ];

  Future<void> _performTranslation() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isTranslating = true);

    final packs = await ref.read(languagePacksProvider.future);
    final matchingPack = packs.firstWhere(
      (p) => p.sourceLang == _sourceLang && p.targetLang == _targetLang && p.isInstalled,
      orElse: () => packs.firstWhere(
        (p) => p.isInstalled,
        orElse: () => packs.first,
      ),
    );

    final result = await OnnxTranslationEngine().translateText(
      text: text,
      sourceLang: _sourceLang,
      targetLang: _targetLang,
      packLocalPath: matchingPack.isInstalled ? matchingPack.localPath : null,
    );

    setState(() {
      _outputController.text = result;
      _isTranslating = false;
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packsAsync = ref.watch(languagePacksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neural Translation Studio'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _sourceLang,
                        decoration: const InputDecoration(labelText: 'From', border: OutlineInputBorder()),
                        items: _langs.map((l) => DropdownMenuItem(value: l['code'], child: Text(l['name']!))).toList(),
                        onChanged: (val) => setState(() => _sourceLang = val!),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.swap_horiz_rounded),
                      onPressed: () {
                        setState(() {
                          final temp = _sourceLang;
                          _sourceLang = _targetLang;
                          _targetLang = temp;
                        });
                      },
                    ),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _targetLang,
                        decoration: const InputDecoration(labelText: 'To', border: OutlineInputBorder()),
                        items: _langs.map((l) => DropdownMenuItem(value: l['code'], child: Text(l['name']!))).toList(),
                        onChanged: (val) => setState(() => _targetLang = val!),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _inputController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Source Text / Dialogue',
                hintText: 'Enter dialogue to translate...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                icon: _isTranslating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.translate_rounded),
                label: const Text('Translate with Neural Engine'),
                onPressed: _isTranslating ? null : _performTranslation,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _outputController,
              maxLines: 5,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Translated Subtitle Output',
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Active Engine Status',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            packsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => const SizedBox.shrink(),
              data: (packs) {
                final hasNeural = packs.any((p) => p.sourceLang == _sourceLang && p.targetLang == _targetLang && p.isInstalled);
                return ListTile(
                  tileColor: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(
                    hasNeural ? Icons.check_circle : Icons.info_outline,
                    color: hasNeural ? Colors.green : Colors.amber,
                  ),
                  title: Text(hasNeural ? 'Engine: ONNX Runtime Neural Transformer' : 'Engine: Rule-Based Synthesizer (Fallback)'),
                  subtitle: Text(
                    hasNeural
                        ? 'High precision offline neural Seq2Seq model loaded.'
                        : 'Download the offline language pack from Language Packs for full neural accuracy.',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
