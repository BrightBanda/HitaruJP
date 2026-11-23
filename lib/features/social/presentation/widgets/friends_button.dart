import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';

/// Opens Friends, with a badge for requests and cheers waiting.
class FriendsButton extends ConsumerWidget {
  const FriendsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(socialBadgeProvider).value ?? 0;
    return IconButton(
      tooltip: 'Friends',
      onPressed: () => context.go('/profile?tab=friends'),
      icon: Badge(
        isLabelVisible: waiting > 0,
        label: Text('$waiting'),
        child: const Icon(Icons.people_outline),
      ),
    );
  }
}
