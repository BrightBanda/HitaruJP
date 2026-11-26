import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';
import 'package:ingrain/features/social/presentation/widgets/person_avatar.dart';
import 'package:share_plus/share_plus.dart';

/// Sends [video] to friends inside the app, or its link anywhere else.
Future<void> showShareVideoSheet(BuildContext context, ContentItem video) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ShareVideoSheet(video: video),
    );

class ShareVideoSheet extends ConsumerStatefulWidget {
  final ContentItem video;

  const ShareVideoSheet({super.key, required this.video});

  @override
  ConsumerState<ShareVideoSheet> createState() => _ShareVideoSheetState();
}

class _ShareVideoSheetState extends ConsumerState<ShareVideoSheet> {
  /// Made once, the first time it is sent, and reused for every friend.
  String? _code;
  final Set<String> _sending = {};
  final Set<String> _sent = {};

  Future<void> _send(Person friend) async {
    if (_sending.contains(friend.username) || _sent.contains(friend.username)) {
      return;
    }
    setState(() => _sending.add(friend.username));
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(socialRepositoryProvider);
    try {
      _code ??= (await repository.createShare(
        kind: ShareKind.playlist,
        title: widget.video.title,
        videos: [
          SharedVideo(
            videoId: widget.video.id,
            title: widget.video.title,
            channelTitle: widget.video.channelTitle,
            thumbnailUrl: widget.video.thumbnailUrl,
          ),
        ],
      )).code;
      await repository.shareWithFriend(friend.username, _code!);
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _sent.add(friend.username));
    } on SocialException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reach the HitaruJP server.')),
      );
    } finally {
      if (mounted) setState(() => _sending.remove(friend.username));
    }
  }

  Future<void> _shareLink() async {
    final link = widget.video.sourceUrl;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${widget.video.title}\n$link\n\nWatching it in HitaruJP to '
              'learn Japanese.',
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Link copied')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(socialMeProvider).value;
    final friends = ref.watch(friendsOverviewProvider);

    Widget friendsSection;
    if (me != null && me.username == null) {
      friendsSection = _Hint(
        text: 'Choose a username to share videos with friends.',
        action: 'Set up friends',
        onTap: () {
          Navigator.of(context).pop();
          context.go('/profile?tab=friends');
        },
      );
    } else {
      friendsSection = friends.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const _Hint(
          text: "Couldn't load your friends. Check your connection.",
        ),
        data: (overview) => overview.friends.isEmpty
            ? _Hint(
                text: 'Add friends to send them videos in the app.',
                action: 'Find people',
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/friends/search');
                },
              )
            : Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final friend in overview.friends)
                    _FriendTarget(
                      friend: friend,
                      sending: _sending.contains(friend.username),
                      sent: _sent.contains(friend.username),
                      onTap: () => _send(friend),
                    ),
                ],
              ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share video', style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              widget.video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('Send to a friend', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            friendsSection,
            const SizedBox(height: 12),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link),
              title: const Text('Share link'),
              subtitle: const Text('Send the YouTube link anywhere'),
              onTap: _shareLink,
            ),
          ],
        ),
      ),
    );
  }
}

/// A friend as a tappable companion, showing whether the video went.
class _FriendTarget extends StatelessWidget {
  final Person friend;
  final bool sending;
  final bool sent;
  final VoidCallback onTap;

  const _FriendTarget({
    required this.friend,
    required this.sending,
    required this.sent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: sent ? 'Sent to ${friend.name}' : 'Send to ${friend.name}',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  PersonAvatar(person: friend, size: 56),
                  if (sending || sent)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: sent ? AppColors.dialogue : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: sent
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : const Padding(
                                padding: EdgeInsets.all(4),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                sent ? 'Sent' : friend.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: sent ? AppColors.dialogue : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onTap;

  const _Hint({required this.text, this.action, this.onTap});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(text)),
      if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
    ],
  );
}
