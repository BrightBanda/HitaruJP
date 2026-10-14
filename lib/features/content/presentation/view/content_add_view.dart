import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/content/presentation/view/add_content_type.dart';
import 'package:ingrain/features/content/presentation/view/youtube_search_results.dart';
import 'package:ingrain/features/dialogue/data/user_dialogue_repository.dart';
import 'package:ingrain/features/dialogue/domain/dialogue_text_parser.dart';
import 'package:ingrain/features/dialogue/presentation/viewmodel/dialogue_providers.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:ingrain/shared/widgets/web_transcript_notice.dart';

class ContentAddView extends ConsumerStatefulWidget {
  final AddContentType initialType;

  const ContentAddView({super.key, this.initialType = AddContentType.youtube});

  @override
  ConsumerState<ContentAddView> createState() => _ContentAddViewState();
}

class _ContentAddViewState extends ConsumerState<ContentAddView> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  final _dialogueController = TextEditingController();
  late AddContentType _type = widget.initialType;
  bool _isFetching = false;
  String? _fetchError;
  String? _youtubeQuery;

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _dialogueController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    switch (_type) {
      case AddContentType.youtube:
        _searchYoutube();
      case AddContentType.dialogue:
        await _submitDialogue();
      case AddContentType.podcast:
        return;
    }
  }

  Future<void> _submitDialogue() async {
    setState(() {
      _isFetching = true;
      _fetchError = null;
    });
    try {
      final dictionary = await ref.read(dictionaryProvider.future);
      final dialogue = const DialogueTextParser().parse(
        id: UserDialogueRepository.newId(),
        title: _titleController.text,
        text: _dialogueController.text,
        dictionary: dictionary,
        now: DateTime.now(),
      );
      await ref.read(userDialogueRepositoryProvider).save(dialogue);
      ref.invalidate(dialogueListViewModelProvider);
      if (mounted) context.pushReplacement('/dialogues/${dialogue.id}');
    } catch (e) {
      if (mounted) setState(() => _fetchError = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  /// Shows YouTube results for what was typed: a link or id resolves to that
  /// one video, anything else is a search.
  void _searchYoutube() {
    final query = _urlController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _youtubeQuery = query);
  }

  @override
  Widget build(BuildContext context) {
    final isDialogue = _type == AddContentType.dialogue;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Content')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(_type.icon, size: 40, color: primary),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<AddContentType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Content type'),
                  borderRadius: BorderRadius.circular(16),
                  items: [
                    for (final type in AddContentType.values)
                      DropdownMenuItem(
                        value: type,
                        enabled: type.isAvailable,
                        child: _TypeLabel(type: type),
                      ),
                  ],
                  onChanged: _isFetching
                      ? null
                      : (type) => setState(() {
                          _type = type ?? _type;
                          _fetchError = null;
                        }),
                ),
                const SizedBox(height: 16),
                if (!isDialogue && WebTranscriptNotice.applies) ...[
                  const WebTranscriptBanner(),
                  const SizedBox(height: 16),
                ],
                if (!isDialogue)
                  TextFormField(
                    controller: _urlController,
                    textInputAction: TextInputAction.search,
                    onFieldSubmitted: (_) => _searchYoutube(),
                    decoration: InputDecoration(
                      labelText: 'Search YouTube or paste a link',
                      hintText: '日本語 vlog, or https://youtu.be/…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _searchYoutube,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Type something to search, or paste a link';
                      }
                      return null;
                    },
                  ),
                if (isDialogue) ...[
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      prefixIcon: Icon(Icons.title),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter a title';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dialogueController,
                    minLines: 6,
                    maxLines: 14,
                    decoration: const InputDecoration(
                      labelText: 'Japanese text',
                      alignLabelWithHint: true,
                      hintText:
                          'Aiko: 今日[きょう]は いい天気[てんき]ですね。 | '
                          'kyou wa ii tenki desu ne | Nice weather today.',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Paste or type the dialogue';
                      }
                      return null;
                    },
                  ),
                ],
                if (isDialogue) ...[
                  const SizedBox(height: 12),
                  const _DialogueFormatHelp(),
                ],
                if (_fetchError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _fetchError!,
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!isDialogue && _youtubeQuery != null) ...[
                  const SizedBox(height: 8),
                  YoutubeSearchResults(query: _youtubeQuery!),
                ],
                if (isDialogue) ...[
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isFetching ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _isFetching
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text('Saving dialogue...'),
                            ],
                          )
                        : const Text('Save dialogue'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dropdown row: coloured icon, name, and a "coming soon" tag when the type
/// cannot be picked yet.
class _TypeLabel extends StatelessWidget {
  final AddContentType type;

  const _TypeLabel({required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final dim = !type.isAvailable;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          type.icon,
          size: 20,
          color: dim ? primary.withValues(alpha: 0.45) : primary,
        ),
        const SizedBox(width: 10),
        Text(
          type.label,
          style: dim
              ? TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                )
              : null,
        ),
        if (dim) ...[
          const SizedBox(width: 8),
          Text('Coming soon', style: theme.textTheme.labelSmall),
        ],
      ],
    );
  }
}

/// How to write a dialogue, shown under the text box.
class _DialogueFormatHelp extends StatelessWidget {
  const _DialogueFormatHelp();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontWeight: FontWeight.w600,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to write it', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text('One line per sentence:', style: theme.textTheme.bodySmall),
          Text('Name: 日本語[にほんご] | romaji | translation', style: code),
          const SizedBox(height: 6),
          Text(
            '• Name: sets the speaker. Leave it out for a story.\n'
            '• 漢字[かんじ] shows kana over that kanji. Kanji you leave '
            'unmarked are filled in from the dictionary.\n'
            '• | separates the parts. Romaji and translation are optional: '
            'with one part after the Japanese it is the translation, or use '
            '|| to skip the romaji.\n'
            '• In the reader, Kana, Romaji and See translation switch each '
            'one on and off.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
