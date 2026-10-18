import 'package:flutter/material.dart';

enum LibraryContentFilter {
  videos(
    icon: Icons.smart_display_outlined,
    title: 'YouTube video',
    description: 'Watch with Japanese subtitles',
  ),
  books(
    icon: Icons.auto_stories_outlined,
    title: 'Books',
    description: 'Short stories adapted for learners',
  ),
  dialogues(
    icon: Icons.forum_outlined,
    title: 'Dialogues and stories',
    description: 'Read conversations and short stories',
  );

  const LibraryContentFilter({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

/// The Library's category picker: one selectable card per kind of content.
class LibraryContentFilterControl extends StatelessWidget {
  final LibraryContentFilter selected;
  final ValueChanged<LibraryContentFilter> onChanged;

  const LibraryContentFilterControl({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final filter in LibraryContentFilter.values) ...[
              if (filter.index > 0) const SizedBox(width: 10),
              Expanded(
                child: _CategoryCard(
                  filter: filter,
                  isSelected: filter == selected,
                  onTap: () => onChanged(filter),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(selected.description, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final LibraryContentFilter filter;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.filter,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final foreground = isSelected ? Colors.white : accent;

    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: isSelected ? accent : accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 88,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(filter.icon, color: foreground, size: 26),
                  const SizedBox(height: 6),
                  Text(
                    filter.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 12,
                      color: foreground,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
