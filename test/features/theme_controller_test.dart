import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/app/theme/theme_controller.dart';
import 'package:ingrain/features/settings/domain/app_settings.dart';
import 'package:ingrain/features/settings/presentation/viewmodel/settings_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_overrides.dart';

void main() {
  late ProviderContainer container;

  Future<void> pump() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final session = FakeAuthSession();
    // The settings repository now lives behind Firestore, so point the document
    // store and auth providers at in-memory stand-ins — a real session must never
    // leak a broadcast stream that keeps the test binding alive.
    container = ProviderContainer(
      overrides: [...appTestOverrides(prefs, session: session)],
    );
    addTearDown(container.dispose);
    addTearDown(session.dispose);
    // Warm up both providers so the projected theme mode is resolved.
    container.read(settingsViewModelProvider);
    await Future<void>.delayed(Duration.zero);
    container.read(themeControllerProvider);
  }

  group('ThemeControllerNotifier', () {
    test('defaults to system when no theme is persisted', () async {
      await pump();

      expect(container.read(themeControllerProvider), ThemeMode.system);
    });

    test('projects a persisted dark setting', () async {
      await pump();

      await container
          .read(settingsViewModelProvider.notifier)
          .setThemeMode(ThemeSetting.dark);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeControllerProvider), ThemeMode.dark);
    });

    test('projects a persisted light setting', () async {
      await pump();

      await container
          .read(settingsViewModelProvider.notifier)
          .setThemeMode(ThemeSetting.light);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeControllerProvider), ThemeMode.light);
    });

    test('setMode switches immediately and persists the choice', () async {
      await pump();

      await container
          .read(themeControllerProvider.notifier)
          .setMode(ThemeMode.dark);

      expect(container.read(themeControllerProvider), ThemeMode.dark);

      final settings = await container
          .read(settingsRepositoryProvider)
          .settings;
      expect(settings.themeMode, ThemeSetting.dark);
    });

    test('setMode back to system keeps following persisted state', () async {
      await pump();

      await container
          .read(themeControllerProvider.notifier)
          .setMode(ThemeMode.dark);
      await container
          .read(themeControllerProvider.notifier)
          .setMode(ThemeMode.system);

      expect(container.read(themeControllerProvider), ThemeMode.system);
      final settings = await container
          .read(settingsRepositoryProvider)
          .settings;
      expect(settings.themeMode, ThemeSetting.system);
    });
  });
}
