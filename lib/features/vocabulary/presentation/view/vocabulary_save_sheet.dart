import 'package:flutter/material.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/srs/domain/deck.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';

class VocabularySaveRequest {
  final String word;
  final String? reading;
  final String? meaning;
  final String? pos;

  /// The deck the word's flashcard goes into.
  final String deckId;

  const VocabularySaveRequest({
    required this.word,
    this.reading,
    this.meaning,
    this.pos,
    this.deckId = minedPhrasesDeckId,
  });
}

/// Save form for a tapped word, pre-filled from the dictionary. Pops a
/// [VocabularySaveRequest] so the caller owns the save.
class VocabularySaveSheet extends StatefulWidget {
  final String title;
  final String word;
  final String? reading;
  final String? meaning;
  final String? pos;
  final String? contextLabel;
  final bool wordEditable;

  const VocabularySaveSheet({
    super.key,
    required this.title,
    required this.word,
    this.reading,
    this.meaning,
    this.pos,
    this.contextLabel,
    this.wordEditable = false,
  });

  @override
  State<VocabularySaveSheet> createState() => _VocabularySaveSheetState();
}

class _VocabularySaveSheetState extends State<VocabularySaveSheet> {
  late final TextEditingController _wordController;
  late final TextEditingController _readingController;
  late final TextEditingController _meaningController;
  String? _errorText;
  String _deckId = minedPhrasesDeckId;

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.word);
    _readingController = TextEditingController(text: widget.reading);
    _meaningController = TextEditingController(text: widget.meaning);
    _wordController.addListener(_maybeAutofillFromRomanizedWord);
  }

  @override
  void dispose() {
    _wordController.removeListener(_maybeAutofillFromRomanizedWord);
    _wordController.dispose();
    _readingController.dispose();
    _meaningController.dispose();
    super.dispose();
  }

  Future<void> _maybeAutofillFromRomanizedWord() async {
    final rawWord = _wordController.text.trim();
    if (rawWord.isEmpty) return;

    final kana = _romajiToKana(rawWord);
    if (kana == null || !RegExp(r"^[a-zA-Z\s\-']+$").hasMatch(rawWord)) {
      return;
    }

    if (_readingController.text.trim().isEmpty ||
        _readingController.text.trim() == widget.reading?.trim()) {
      if (mounted) {
        setState(() {
          _readingController.text = kana;
          _readingController.selection = TextSelection.collapsed(
            offset: _readingController.text.length,
          );
        });
      }
    }

    final dictionary = await ProviderScope.containerOf(context)
        .read(dictionaryProvider.future);
    final entry = dictionary.lookup(kana) ?? dictionary.lookup(rawWord);
    if (!mounted || entry == null) return;

    if (_meaningController.text.trim().isEmpty ||
        _meaningController.text.trim() == widget.meaning?.trim()) {
      if (mounted) {
        setState(() {
          _meaningController.text = entry.primaryMeaning;
          _meaningController.selection = TextSelection.collapsed(
            offset: _meaningController.text.length,
          );
        });
      }
    }
  }

  void _submit() {
    final word = _wordController.text.trim();
    if (word.isEmpty) {
      setState(() => _errorText = 'Word is required');
      return;
    }
    Navigator.of(context).pop(
      VocabularySaveRequest(
        word: word,
        reading: _nullable(_readingController.text),
        meaning: _nullable(_meaningController.text),
        pos: null,
        deckId: _deckId,
      ),
    );
  }

  static String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _wordController,
                readOnly: !widget.wordEditable,
                style: const TextStyle(fontSize: 20),
                decoration: InputDecoration(
                  labelText: 'Word',
                  helperText: widget.wordEditable
                      ? 'Required'
                      : 'Taken from the transcript',
                ),
              ),
              if (widget.contextLabel != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryMain.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.contextLabel!,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontSize: 13, height: 1.5),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _readingController,
                decoration: const InputDecoration(labelText: 'Reading (kana)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _meaningController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Meaning'),
              ),
              const SizedBox(height: 12),
              _DeckPicker(
                deckId: _deckId,
                onChanged: (id) => setState(() => _deckId = id),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                style: accentButtonStyle(AppColors.primaryMain),
                onPressed: _submit,
                icon: const Icon(Icons.bookmark_add),
                label: const Text('Save word'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _romajiToKana(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty || text.contains(RegExp(r'[ぁ-ゖァ-ヶ]'))) {
      return null;
    }

    final replacements = <MapEntry<String, String>>[
      const MapEntry('kyou', 'きょう'),
      const MapEntry('kyo', 'きょ'),
      const MapEntry('kya', 'きゃ'),
      const MapEntry('kyu', 'きゅ'),
      const MapEntry('kya', 'きゃ'),
      const MapEntry('shou', 'しょう'),
      const MapEntry('sho', 'しょ'),
      const MapEntry('sha', 'しゃ'),
      const MapEntry('shu', 'しゅ'),
      const MapEntry('shi', 'し'),
      const MapEntry('chou', 'ちょう'),
      const MapEntry('cho', 'ちょ'),
      const MapEntry('cha', 'ちゃ'),
      const MapEntry('chu', 'ちゅ'),
      const MapEntry('chi', 'ち'),
      const MapEntry('jou', 'じょう'),
      const MapEntry('jo', 'じょ'),
      const MapEntry('ja', 'じゃ'),
      const MapEntry('ju', 'じゅ'),
      const MapEntry('ji', 'じ'),
      const MapEntry('nyou', 'にょう'),
      const MapEntry('nyo', 'にょ'),
      const MapEntry('nya', 'にゃ'),
      const MapEntry('nyu', 'にゅ'),
      const MapEntry('ni', 'に'),
      const MapEntry('hyou', 'ひょう'),
      const MapEntry('hyo', 'ひょ'),
      const MapEntry('hya', 'ひゃ'),
      const MapEntry('hyu', 'ひゅ'),
      const MapEntry('hi', 'ひ'),
      const MapEntry('myou', 'みょう'),
      const MapEntry('myo', 'みょ'),
      const MapEntry('mya', 'みゃ'),
      const MapEntry('myu', 'みゅ'),
      const MapEntry('mi', 'み'),
      const MapEntry('ryou', 'りょう'),
      const MapEntry('ryo', 'りょ'),
      const MapEntry('rya', 'りゃ'),
      const MapEntry('ryu', 'りゅ'),
      const MapEntry('ri', 'り'),
      const MapEntry('you', 'よう'),
      const MapEntry('yo', 'よ'),
      const MapEntry('ya', 'や'),
      const MapEntry('yu', 'ゆ'),
      const MapEntry('wa', 'わ'),
      const MapEntry('wo', 'を'),
      const MapEntry('n', 'ん'),
      const MapEntry('tsu', 'つ'),
      const MapEntry('to', 'と'),
      const MapEntry('ta', 'た'),
      const MapEntry('te', 'て'),
      const MapEntry('ti', 'ち'),
      const MapEntry('tu', 'つ'),
      const MapEntry('di', 'ぢ'),
      const MapEntry('du', 'づ'),
      const MapEntry('do', 'ど'),
      const MapEntry('da', 'だ'),
      const MapEntry('de', 'で'),
      const MapEntry('ko', 'こ'),
      const MapEntry('ka', 'か'),
      const MapEntry('ki', 'き'),
      const MapEntry('ku', 'く'),
      const MapEntry('ke', 'け'),
      const MapEntry('sa', 'さ'),
      const MapEntry('su', 'す'),
      const MapEntry('se', 'せ'),
      const MapEntry('so', 'そ'),
      const MapEntry('ha', 'は'),
      const MapEntry('hi', 'ひ'),
      const MapEntry('fu', 'ふ'),
      const MapEntry('he', 'へ'),
      const MapEntry('ho', 'ほ'),
      const MapEntry('ma', 'ま'),
      const MapEntry('mi', 'み'),
      const MapEntry('mu', 'む'),
      const MapEntry('me', 'め'),
      const MapEntry('mo', 'も'),
      const MapEntry('na', 'な'),
      const MapEntry('ni', 'に'),
      const MapEntry('nu', 'ぬ'),
      const MapEntry('ne', 'ね'),
      const MapEntry('no', 'の'),
      const MapEntry('ra', 'ら'),
      const MapEntry('ri', 'り'),
      const MapEntry('ru', 'る'),
      const MapEntry('re', 'れ'),
      const MapEntry('ro', 'ろ'),
      const MapEntry('ga', 'が'),
      const MapEntry('gi', 'ぎ'),
      const MapEntry('gu', 'ぐ'),
      const MapEntry('ge', 'げ'),
      const MapEntry('go', 'ご'),
      const MapEntry('za', 'ざ'),
      const MapEntry('zi', 'じ'),
      const MapEntry('zu', 'ず'),
      const MapEntry('ze', 'ぜ'),
      const MapEntry('zo', 'ぞ'),
      const MapEntry('ba', 'ば'),
      const MapEntry('bi', 'び'),
      const MapEntry('bu', 'ぶ'),
      const MapEntry('be', 'べ'),
      const MapEntry('bo', 'ぼ'),
      const MapEntry('pa', 'ぱ'),
      const MapEntry('pi', 'ぴ'),
      const MapEntry('pu', 'ぷ'),
      const MapEntry('pe', 'ぺ'),
      const MapEntry('po', 'ぽ'),
      const MapEntry('a', 'あ'),
      const MapEntry('i', 'い'),
      const MapEntry('u', 'う'),
      const MapEntry('e', 'え'),
      const MapEntry('o', 'お'),
    ];

    final buffer = StringBuffer();
    var cursor = 0;
    while (cursor < text.length) {
      var matched = false;
      for (final replacement
          in replacements.where((entry) => entry.key.isNotEmpty).toList()
            ..sort((a, b) => b.key.length.compareTo(a.key.length))) {
        final key = replacement.key;
        if (text.startsWith(key, cursor)) {
          buffer.write(replacement.value);
          cursor += key.length;
          matched = true;
          break;
        }
      }
      if (!matched) {
        final char = text[cursor];
        buffer.write(char);
        cursor += 1;
      }
    }

    final kana = buffer.toString();
    return kana.isEmpty ? null : kana;
  }
}

/// The decks a word can go into, plus "New deck…" to make one on the spot.
final _saveDecksProvider = FutureProvider.autoDispose<List<Deck>>(
  (ref) => ref.watch(deckRepositoryProvider).listDecks(),
);

class _DeckPicker extends ConsumerWidget {
  static const _newDeck = '__new__';

  final String deckId;
  final ValueChanged<String> onChanged;

  const _DeckPicker({required this.deckId, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(_saveDecksProvider).value ?? [Deck.minedPhrases];
    // A deck deleted meanwhile falls back to the built-in one.
    final value = decks.any((deck) => deck.id == deckId)
        ? deckId
        : minedPhrasesDeckId;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Deck',
        prefixIcon: Icon(Icons.style_outlined),
      ),
      items: [
        for (final deck in decks)
          DropdownMenuItem(
            value: deck.id,
            child: Text(deck.name, overflow: TextOverflow.ellipsis),
          ),
        const DropdownMenuItem(
          value: _newDeck,
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('New deck…'),
            ],
          ),
        ),
      ],
      onChanged: (id) async {
        if (id == null) return;
        if (id != _newDeck) return onChanged(id);
        final name = await showDialog<String>(
          context: context,
          builder: (_) => const _NewDeckDialog(),
        );
        if (name == null) return;
        final deck = await ref.read(deckRepositoryProvider).createDeck(name);
        ref.invalidate(_saveDecksProvider);
        ref.invalidate(deckSummariesProvider);
        onChanged(deck.id);
      },
    );
  }
}

class _NewDeckDialog extends StatefulWidget {
  const _NewDeckDialog();

  @override
  State<_NewDeckDialog> createState() => _NewDeckDialogState();
}

class _NewDeckDialogState extends State<_NewDeckDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New deck'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Deck name'),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
