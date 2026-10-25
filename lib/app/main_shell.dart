import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/widgets/home_tour.dart';
import 'package:ingrain/features/profile/presentation/widgets/learner_avatar.dart';
import 'package:ingrain/shared/layout/window_size.dart';
import 'package:ingrain/shared/widgets/app_logo.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:ingrain/shared/widgets/double_back_to_exit.dart';

/// The pages behind the Learn tab's drop-up menu.
enum LearnDestination {
  vocab('Vocab', Icons.translate, '/learn/vocab'),
  kana('Kana', Icons.font_download_outlined, '/learn/kana');

  const LearnDestination(this.label, this.icon, this.path);

  final String label;
  final IconData icon;
  final String path;
}

/// A place in the app's main navigation.
typedef _Destination = ({
  IconData icon,
  IconData selectedIcon,
  String label,
  String path,
});

/// The frame around the main pages: a bottom bar on phones, a side rail on
/// tablets and small windows, and a full sidebar on desktop.
class MainShellView extends StatelessWidget {
  final Widget child;

  const MainShellView({super.key, required this.child});

  /// Phone tabs. Learn has no page of its own: it opens a menu of
  /// [LearnDestination]s, which keeps the bottom bar to five items.
  static const _tabs = [
    (Icons.play_circle_fill, 'Immerse', '/immerse'),
    (Icons.video_library, 'Library', '/library'),
    (Icons.style, 'Flashcards', '/flashcards'),
    (Icons.school, 'Learn', '/learn'),
    (Icons.person, 'Profile', '/profile'),
  ];

  static const _learnIndex = 3;

  /// Wide-screen destinations. With room to spare, Vocab and Kana get their
  /// own entries instead of hiding behind Learn.
  static const List<_Destination> _destinations = [
    (
      icon: Icons.play_circle_outline,
      selectedIcon: Icons.play_circle_fill,
      label: 'Immerse',
      path: '/immerse',
    ),
    (
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library,
      label: 'Library',
      path: '/library',
    ),
    (
      icon: Icons.style_outlined,
      selectedIcon: Icons.style,
      label: 'Flashcards',
      path: '/flashcards',
    ),
    (
      icon: Icons.translate_outlined,
      selectedIcon: Icons.translate,
      label: 'Vocab',
      path: '/learn/vocab',
    ),
    (
      icon: Icons.font_download_outlined,
      selectedIcon: Icons.font_download,
      label: 'Kana',
      path: '/learn/kana',
    ),
    (
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Profile',
      path: '/profile',
    ),
  ];

  /// Pages that lay out their own columns get the full page width; the rest
  /// are lists and read best narrower.
  static double _contentWidth(String location) =>
      location.startsWith('/immerse') || location.startsWith('/profile')
      ? MaxWidth.page
      : 980;

  @override
  Widget build(BuildContext context) {
    final windowSize = WindowSize.of(context);
    if (windowSize.isCompact) return _buildCompact(context);

    final location = GoRouterState.of(context).uri.path;
    final selected = _destinations.indexWhere(
      (d) => location.startsWith(d.path),
    );
    final navigation = windowSize == WindowSize.expanded
        ? _Sidebar(
            destinations: _destinations,
            selectedIndex: selected < 0 ? 0 : selected,
          )
        : _Rail(
            destinations: _destinations,
            selectedIndex: selected < 0 ? 0 : selected,
          );

    return DoubleBackToExit(
      child: Scaffold(
        body: Row(
          children: [
            navigation,
            Expanded(
              child: MaxWidth(maxWidth: _contentWidth(location), child: child),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return DoubleBackToExit(
      child: Scaffold(
        body: child,
        bottomNavigationBar: Builder(
          builder: (barContext) => NavigationBar(
            selectedIndex: _currentIndex(context),
            onDestinationSelected: (index) {
              if (index == _learnIndex) {
                _openLearnMenu(barContext);
              } else {
                context.go(_tabs[index].$3);
              }
            },
            destinations: [
              for (final (index, tab) in _tabs.indexed)
                NavigationDestination(
                  // Only the unselected icon carries the key: the home tour
                  // points at these tabs while the learner is on Immerse.
                  icon: KeyedSubtree(
                    key: _tourKey(tab.$3),
                    child: Icon(tab.$1),
                  ),
                  selectedIcon: Icon(tab.$1),
                  label: tab.$2,
                  tooltip: index == _learnIndex ? 'Learn: vocab or kana' : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The home tour's target for the destination at [path], if it has one.
  static GlobalKey? _tourKey(String path) => switch (path) {
    '/library' => HomeTourTargets.library,
    '/flashcards' => HomeTourTargets.flashcards,
    _ => null,
  };

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _tabs.indexWhere((t) => location.startsWith(t.$3));
    return index < 0 ? 0 : index;
  }

  /// A menu that opens upwards from the Learn tab.
  Future<void> _openLearnMenu(BuildContext barContext) async {
    final bar = barContext.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(barContext).context.findRenderObject()! as RenderBox;
    final barTopLeft = bar.localToGlobal(Offset.zero, ancestor: overlay);
    final tabWidth = bar.size.width / _tabs.length;
    final tabLeft = barTopLeft.dx + tabWidth * _learnIndex;

    // Menus open downwards from `top`; start them one menu-height above the
    // bar so they sit on top of it instead.
    const itemHeight = kMinInteractiveDimension;
    const menuHeight = itemHeight * 2 + 16;
    final top = barTopLeft.dy - menuHeight - 8;

    final destination = await showMenu<LearnDestination>(
      context: barContext,
      position: RelativeRect.fromLTRB(
        tabLeft - 40,
        top,
        overlay.size.width - tabLeft - tabWidth,
        overlay.size.height - barTopLeft.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        for (final destination in LearnDestination.values)
          PopupMenuItem(
            value: destination,
            height: itemHeight,
            child: Row(
              children: [
                Icon(
                  destination.icon,
                  color: Theme.of(barContext).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(destination.label),
              ],
            ),
          ),
      ],
    );
    if (destination != null && barContext.mounted) {
      barContext.go(destination.path);
    }
  }
}

/// Tablets and small windows: icons with labels down the side.
class _Rail extends StatelessWidget {
  final List<_Destination> destinations;
  final int selectedIndex;

  const _Rail({required this.destinations, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: selectedIndex,
        labelType: NavigationRailLabelType.all,
        indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.14),
        leading: const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 16),
          child: AppLogo.mark(size: 48),
        ),
        trailing: Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Tooltip(
                message: 'Your profile',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.go('/profile'),
                  child: const LearnerAvatar(size: 44, rounded: true),
                ),
              ),
            ),
          ),
        ),
        onDestinationSelected: (index) => context.go(destinations[index].path),
        destinations: [
          for (final d in destinations)
            NavigationRailDestination(
              icon: KeyedSubtree(
                key: MainShellView._tourKey(d.path),
                child: Icon(d.icon),
              ),
              selectedIcon: Icon(d.selectedIcon),
              label: Text(d.label),
            ),
        ],
      ),
    );
  }
}

/// Desktop: a full sidebar with the logo, labelled destinations and the
/// learner's own card at the bottom.
class _Sidebar extends ConsumerWidget {
  final List<_Destination> destinations;
  final int selectedIndex;

  const _Sidebar({required this.destinations, required this.selectedIndex});

  static const width = 248.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authViewModelProvider);
    final name = auth.displayName?.trim();
    final level = auth.profile?.effectiveLevel;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const AppLogo.mark(size: 44),
                  const SizedBox(width: 12),
                  // Shrinks rather than overflowing at large text sizes.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'HitaruJP',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              for (final (index, d) in destinations.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: KeyedSubtree(
                    key: MainShellView._tourKey(d.path),
                    child: _SidebarItem(
                      destination: d,
                      selected: index == selectedIndex,
                    ),
                  ),
                ),
              const Spacer(),
              TintedSurface(
                color: theme.colorScheme.primary,
                alpha: 0.07,
                radius: 18,
                padding: const EdgeInsets.all(10),
                onTap: () => context.go('/profile'),
                child: Row(
                  children: [
                    const LearnerAvatar(size: 44, rounded: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name == null || name.isEmpty ? 'Learner' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          if (level != null)
                            Text(
                              '${level.code} · ${level.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _Destination destination;
  final bool selected;

  const _SidebarItem({required this.destination, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(destination.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: selected
                      ? primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 14),
                Text(
                  destination.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? primary : null,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
