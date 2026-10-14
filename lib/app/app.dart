import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/app/router.dart';
import 'package:ingrain/app/theme/app_theme.dart';
import 'package:ingrain/app/theme/theme_controller.dart';
import 'package:ingrain/core/lifecycle.dart';
import 'package:ingrain/features/profile/presentation/viewmodel/profile_sync_providers.dart';

class IngrApp extends ConsumerWidget {
  const IngrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    final router = ref.watch(appRouterProvider);
    ref.watch(appLifecycleObserverProvider);
    // Keeps the server's copy of the profile current and counts visits.
    ref.watch(activityTrackerProvider);

    return MaterialApp.router(
      title: 'HitaruJP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
