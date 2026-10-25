import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/catalog/presentation/viewmodel/catalog_providers.dart';
import 'package:ingrain/features/catalog/presentation/widgets/daily_picks_section.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/view/add_content_type.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/presentation/viewmodel/dialogue_providers.dart';
import 'package:ingrain/features/onboarding/presentation/widgets/home_tour.dart';
import 'package:ingrain/features/progress/domain/progress_summary.dart';
import 'package:ingrain/features/profile/presentation/widgets/learner_avatar.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/shared/layout/window_size.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:ingrain/shared/widgets/skeleton.dart';
import 'package:ingrain/shared/widgets/video_thumbnail.dart';

class ImmersionHomeView extends ConsumerWidget {
  const ImmersionHomeView({super.key});

  static const recentLimit = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentList = ref.watch(contentViewModelProvider);
    final dialogues = ref.watch(dialogueListViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('HitaruJP'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => context.push('/search'),
          ),
          const _AddContentMenu(),
          const SizedBox(width: 12),
        ],
      ),
      body: HomeTourLauncher(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.refresh(contentViewModelProvider.future),
              ref.read(dialogueListViewModelProvider.notifier).refresh(),
              ref.read(progressViewModelProvider.notifier).refresh(),
              ref
                  .refresh(dailyPicksProvider.future)
                  .then<void>((_) {}, onError: (_) {}),
              ref
                  .refresh(levelVideosProvider.future)
                  .then<void>((_) {}, onError: (_) {}),
            ]);
          },
          child: contentList.when(
            data: (items) => _buildHome(context, ref, items, dialogues),
            loading: () => const _HomeSkeleton(),
            error: (_, _) =>
                const Center(child: Text('Failed to load content')),
          ),
        ),
      ),
    );
  }

  Widget _buildHome(
    BuildContext context,
    WidgetRef ref,
    List<ContentItem> items,
    AsyncValue<List<DialogueSummary>> dialogues,
  ) {
    final theme = Theme.of(context);
    final name = ref.watch(authViewModelProvider).displayName?.trim();
    final summary = ref.watch(progressViewModelProvider).summary;
    final recents = recentContent(items, limit: recentLimit);
    final video = recommendedVideo(items);
    final dialogue = dialogueOfTheDay(
      // Books have their own shelf in the Library.
      [
        for (final item in dialogues.value ?? const <DialogueSummary>[])
          if (item.kind != DialogueKind.book) item,
      ],
      DateTime.now(),
    );

    // Wide windows already show the avatar in the sidebar.
    final showAvatar = WindowSize.of(context).isCompact;
    final greeting = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name == null || name.isEmpty ? 'おかえり!' : 'おかえり, $name',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Pick up where you left off, or try something new.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (showAvatar) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => context.go('/profile'),
              child: const LearnerAvatar(size: 52, rounded: true),
            ),
          ],
        ],
      ),
    );
    final hero = KeyedSubtree(
      key: HomeTourTargets.goal,
      child: _HeroCard(
        summary: summary,
        continueItem: recents.firstOrNull,
        dialogue: dialogue,
      ),
    );
    final shortcuts = _Shortcuts(dueCount: summary?.dueCount);
    final picks = DailyPicksSection(
      key: HomeTourTargets.picks,
      // Offline with nothing cached: fall back to the learner's own library.
      fallback: video == null
          ? _PromptTile(
              color: AppColors.video,
              icon: Icons.smart_display_outlined,
              title: 'Add your first YouTube video',
              subtitle: 'Paste a link and the transcript comes with it',
              onTap: () => context.push(AddContentType.youtube.route),
            )
          : _VideoHeroCard(item: video),
    );
    final dialogueSection = <Widget>[
      SectionHeader(
        'Dialogue of the day',
        onAction: () => context.go('/library'),
      ),
      dialogues.when(
        data: (_) => dialogue == null
            ? _PromptTile(
                color: AppColors.dialogue,
                icon: Icons.forum_outlined,
                title: 'Write your own dialogue',
                subtitle: 'Paste any Japanese text to read it here',
                onTap: () => context.push(AddContentType.dialogue.route),
              )
            : _DialogueCard(dialogue: dialogue),
        loading: () => const _LoadingTile(color: AppColors.dialogue),
        error: (_, _) => _PromptTile(
          color: AppColors.dialogue,
          icon: Icons.cloud_off_outlined,
          title: 'Dialogues are unavailable',
          subtitle: 'Tap to try again',
          onTap: () =>
              ref.read(dialogueListViewModelProvider.notifier).refresh(),
        ),
      ),
    ];
    final recentSection = <Widget>[
      if (recents.isNotEmpty) ...[
        SectionHeader('Recent', onAction: () => context.go('/library')),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recents.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _RecentCard(item: recents[index]),
          ),
        ),
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoColumnMinWidth) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              greeting,
              const SizedBox(height: 16),
              hero,
              const SizedBox(height: 12),
              shortcuts,
              picks,
              const LevelShelf(),
              ...dialogueSection,
              ...recentSection,
            ],
          );
        }

        // Wide: what to watch fills the main column; today's goal and the
        // study shortcuts stay at hand in a side column.
        return ListView(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 40),
          children: [
            greeting,
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [picks, const LevelShelf(), ...recentSection],
                  ),
                ),
                const SizedBox(width: 28),
                SizedBox(
                  width: _sideColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 22),
                      hero,
                      const SizedBox(height: 12),
                      shortcuts,
                      ...dialogueSection,
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Below this the page is one column, as on a phone.
  static const _twoColumnMinWidth = 900.0;
  static const _sideColumnWidth = 360.0;
}

/// Most recently opened first.
@visibleForTesting
List<ContentItem> recentContent(List<ContentItem> items, {required int limit}) {
  final sorted = [...items]
    ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
  return sorted.take(limit).toList();
}

/// The video the user has spent the least time with, newest first on ties.
///
/// The fallback when today's catalogue picks cannot be loaded: whatever the
/// learner added to their own library but has barely watched.
@visibleForTesting
ContentItem? recommendedVideo(List<ContentItem> items) {
  if (items.isEmpty) return null;
  final sorted = [...items]
    ..sort((a, b) {
      final byTime = a.totalImmersionSeconds.compareTo(b.totalImmersionSeconds);
      if (byTime != 0) return byTime;
      return b.lastOpenedAt.compareTo(a.lastOpenedAt);
    });
  return sorted.first;
}

/// Rotates through the catalogue one dialogue per calendar day.
@visibleForTesting
DialogueSummary? dialogueOfTheDay(List<DialogueSummary> items, DateTime now) {
  if (items.isEmpty) return null;
  final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
  final day = DateTime.utc(now.year, now.month, now.day);
  final dayNumber = day.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  return sorted[dayNumber % sorted.length];
}

/// The app bar's Add button: a dropdown of the content types.
class _AddContentMenu extends StatelessWidget {
  const _AddContentMenu();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(-64, 6),
      menuChildren: [
        for (final type in AddContentType.values)
          MenuItemButton(
            leadingIcon: Icon(
              type.icon,
              color: type.isAvailable
                  ? type.color
                  : type.color.withValues(alpha: 0.4),
            ),
            trailingIcon: type.isAvailable
                ? null
                : Text('Soon', style: theme.textTheme.labelSmall),
            onPressed: type.isAvailable ? () => context.push(type.route) : null,
            child: Text(type.label),
          ),
      ],
      builder: (context, controller, _) => FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.add, size: 20),
        label: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('Add'), Icon(Icons.arrow_drop_down, size: 20)],
        ),
      ),
    );
  }
}

/// Today's goal, the streak, and the one button that gets you going.
class _HeroCard extends StatelessWidget {
  final ProgressSummary? summary;
  final ContentItem? continueItem;
  final DialogueSummary? dialogue;

  const _HeroCard({this.summary, this.continueItem, this.dialogue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = this.summary;
    final goalMinutes = summary?.dailyGoalMinutes ?? 0;
    final todayMinutes = (summary?.todaySeconds ?? 0) ~/ 60;
    final progress = goalMinutes <= 0
        ? 0.0
        : (todayMinutes / goalMinutes).clamp(0.0, 1.0);
    final streak = summary?.currentStreak ?? 0;

    final item = continueItem;
    final dialogue = this.dialogue;
    final (subtitle, route) = item != null
        ? ('Continue · ${item.title}', '/content/${item.id}')
        : dialogue != null
        ? ('Read · ${dialogue.title}', '/dialogues/${dialogue.id}')
        : ('Add a video to get started', AddContentType.youtube.route);

    const onHero = Colors.white;
    return GradientPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's goal",
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: onHero.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary == null
                          ? '— min'
                          : '$todayMinutes / $goalMinutes min',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: onHero,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: onHero.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      color: AppColors.review,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$streak day${streak == 1 ? '' : 's'}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: onHero,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: onHero,
              backgroundColor: onHero.withValues(alpha: 0.25),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: onHero,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.push(route),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: AppColors.heroGradient,
                        ),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: onHero,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Start immersing',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppColors.primaryDark,
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.primaryMain,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One-tap routes to the study tools, each in its own colour.
class _Shortcuts extends StatelessWidget {
  final int? dueCount;

  const _Shortcuts({this.dueCount});

  @override
  Widget build(BuildContext context) {
    final due = dueCount;
    return Row(
      children: [
        Expanded(
          child: _ShortcutTile(
            color: AppColors.review,
            icon: Icons.style,
            label: 'Flashcards',
            value: due == null ? null : '$due due',
            onTap: () => context.go('/flashcards'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ShortcutTile(
            color: AppColors.vocabulary,
            icon: Icons.translate,
            label: 'Words',
            onTap: () => context.go('/learn/vocab'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ShortcutTile(
            color: AppColors.sentences,
            icon: Icons.font_download_outlined,
            label: 'Kana',
            onTap: () => context.go('/learn/kana'),
          ),
        ),
      ],
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
              Text(
                value ?? 'Open',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoHeroCard extends StatelessWidget {
  final ContentItem item;

  const _VideoHeroCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => context.push('/content/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoThumbnail(item: item, iconSize: 56),
                  const Center(
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.video,
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.totalImmersionSeconds >= 60
                        ? '${item.totalImmersionSeconds ~/ 60} min immersed'
                        : 'Not watched yet',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final ContentItem item;

  const _RecentCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 168,
      child: Card(
        child: InkWell(
          onTap: () => context.push('/content/${item.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 92,
                width: double.infinity,
                child: VideoThumbnail(item: item, iconSize: 32),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(height: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogueCard extends StatelessWidget {
  final DialogueSummary dialogue;

  const _DialogueCard({required this.dialogue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStory = dialogue.kind == DialogueKind.story;
    const accent = AppColors.dialogue;
    final kindColor = isStory ? AppColors.story : AppColors.dialogue;

    return Material(
      color: accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/dialogues/${dialogue.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: kindColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isStory ? Icons.menu_book : Icons.forum,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dialogue.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: kindColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            dialogue.level,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${dialogue.lineCount} lines',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tinted call to action for an empty or failed section.
class _PromptTile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PromptTile({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  final Color color;

  const _LoadingTile({required this.color});

  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: Container(
      height: 84,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const SkeletonBox(width: 48, height: 48, radius: 14),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonBox.line(widthFactor: 0.7, height: 14),
                const SizedBox(height: 8),
                SkeletonBox.line(widthFactor: 0.45),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The home page's shape while the library loads: the greeting, today's goal,
/// the shortcuts and the first picks, as placeholders in place.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView(
        // Scrollable, so pull-to-refresh still works while loading.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox.line(widthFactor: 0.55, height: 22),
                    const SizedBox(height: 8),
                    SkeletonBox.line(widthFactor: 0.8),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const SkeletonBox(width: 52, height: 52, radius: 16),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(height: 168, radius: 24),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                const Expanded(child: SkeletonBox(height: 76, radius: 18)),
              ],
            ],
          ),
          const SizedBox(height: 22),
          SkeletonBox.line(widthFactor: 0.4, height: 16),
          const SizedBox(height: 12),
          const AspectRatio(
            aspectRatio: 16 / 9,
            child: SkeletonBox(height: double.infinity, radius: 18),
          ),
          const SizedBox(height: 10),
          const SkeletonBox(height: 92, radius: 18),
          const SizedBox(height: 10),
          const SkeletonBox(height: 92, radius: 18),
        ],
      ),
    );
  }
}
