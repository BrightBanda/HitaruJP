import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';
import 'package:share_plus/share_plus.dart';

/// Uploads a snapshot of a playlist or deck and shows its code, ready to
/// send to a friend. Anyone with the code can import it.
Future<void> shareCollection(
  BuildContext context,
  WidgetRef ref, {
  required ShareKind kind,
  required String title,
  List<SharedVideo> videos = const [],
  List<SharedCard> cards = const [],
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  SharedCollection? shared;
  String? problem;
  try {
    shared = await ref
        .read(socialRepositoryProvider)
        .createShare(kind: kind, title: title, videos: videos, cards: cards);
  } on SocialException catch (error) {
    problem = error.message;
  } catch (_) {
    problem = 'Could not reach the HitaruJP server.';
  }
  navigator.pop();
  if (shared == null) {
    messenger.showSnackBar(SnackBar(content: Text(problem!)));
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _ShareCodeDialog(shared: shared!),
  );
}

/// The text a learner sends: what it is and how to open it.
String shareMessage(SharedCollection shared) {
  final what = shared.kind == ShareKind.playlist
      ? 'playlist'
      : 'flashcard deck';
  return 'Try my HitaruJP $what "${shared.title}"! In the app, tap Import '
      '(the download icon) in Library or Flashcards and enter the code '
      '${shared.code}';
}

class _ShareCodeDialog extends StatelessWidget {
  final SharedCollection shared;

  const _ShareCodeDialog({required this.shared});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Share "${shared.title}"'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Friends can import it with this code:'),
          const SizedBox(height: 16),
          SelectableText(
            shared.code,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${shared.itemCount} '
            '${shared.kind == ShareKind.playlist ? 'videos' : 'cards'}, as '
            'they are now.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: shared.code));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Code copied')));
            }
          },
          child: const Text('Copy code'),
        ),
        FilledButton.icon(
          onPressed: () async {
            try {
              await SharePlus.instance.share(
                ShareParams(text: shareMessage(shared)),
              );
            } catch (_) {
              await Clipboard.setData(
                ClipboardData(text: shareMessage(shared)),
              );
            }
          },
          icon: const Icon(Icons.ios_share),
          label: const Text('Send'),
        ),
      ],
    );
  }
}
