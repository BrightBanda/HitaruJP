import 'dart:math';

import 'package:ingrain/core/storage/document_store.dart';
import 'package:ingrain/features/auth/domain/auth_repository.dart';
import 'package:ingrain/features/srs/domain/srs_settings.dart';

/// Scheduler settings at `users/{uid}/srs/settings`, and each day's per-deck
/// study counts at `users/{uid}/srsDaily/{yyyy-mm-dd}` (what the daily new
/// and review limits are measured against).
class SrsSettingsRepository {
  final DocumentStore _store;
  final AuthRepository _auth;

  SrsSettingsRepository(this._store, this._auth);

  static const settingsCollection = 'srs';
  static const settingsDoc = 'settings';
  static const dailyCollection = 'srsDaily';

  Future<SrsSettings> load() async {
    final uid = await _auth.ensureUid();
    return fromMap(await _store.getDoc(uid, settingsCollection, settingsDoc));
  }

  Future<void> save(SrsSettings settings) async {
    final uid = await _auth.ensureUid();
    await _store.setDoc(uid, settingsCollection, settingsDoc, toMap(settings));
  }

  /// Per deck: how many new cards and reviews were studied on [day].
  Future<Map<String, DailyStudyCounts>> countsFor(DateTime day) async {
    final uid = await _auth.ensureUid();
    final doc = await _store.getDoc(uid, dailyCollection, dayKey(day));
    return {
      for (final MapEntry(:key, :value) in doc.entries)
        if (value is Map)
          key: DailyStudyCounts(
            newStudied: (value['new'] as num?)?.toInt() ?? 0,
            reviewsDone: (value['reviews'] as num?)?.toInt() ?? 0,
          ),
    };
  }

  /// Records one answer against [deckId]'s limits for [day].
  Future<void> recordStudied(
    DateTime day,
    String deckId, {
    required bool wasNew,
    required bool wasReview,
  }) => _adjust(day, deckId, wasNew: wasNew, wasReview: wasReview, by: 1);

  /// Takes back what [recordStudied] counted, when an answer is undone.
  Future<void> unrecordStudied(
    DateTime day,
    String deckId, {
    required bool wasNew,
    required bool wasReview,
  }) => _adjust(day, deckId, wasNew: wasNew, wasReview: wasReview, by: -1);

  Future<void> _adjust(
    DateTime day,
    String deckId, {
    required bool wasNew,
    required bool wasReview,
    required int by,
  }) async {
    if (!wasNew && !wasReview) return;
    final uid = await _auth.ensureUid();
    final counts = await countsFor(day);
    final current = counts[deckId] ?? const DailyStudyCounts();
    await _store.setDoc(uid, dailyCollection, dayKey(day), {
      deckId: {
        'new': max(0, current.newStudied + (wasNew ? by : 0)),
        'reviews': max(0, current.reviewsDone + (wasReview ? by : 0)),
      },
    }, merge: true);
  }

  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> toMap(SrsSettings s) => {
    'newCardsPerDay': s.newCardsPerDay,
    'maximumReviewsPerDay': s.maximumReviewsPerDay,
    'learningSteps': [for (final d in s.learningSteps) d.inSeconds],
    'relearningSteps': [for (final d in s.relearningSteps) d.inSeconds],
    'graduatingIntervalDays': s.graduatingIntervalDays,
    'easyIntervalDays': s.easyIntervalDays,
    'startingEase': s.startingEase,
    'easyBonus': s.easyBonus,
    'hardIntervalMultiplier': s.hardIntervalMultiplier,
    'intervalModifier': s.intervalModifier,
    'maximumIntervalDays': s.maximumIntervalDays,
    'lapseIntervalFactor': s.lapseIntervalFactor,
  };

  /// Missing or malformed fields fall back to Anki's defaults one by one.
  static SrsSettings fromMap(Map<String, dynamic> map) {
    const d = SrsSettings();
    int integer(String key, int fallback) =>
        (map[key] as num?)?.toInt() ?? fallback;
    double decimal(String key, double fallback) =>
        (map[key] as num?)?.toDouble() ?? fallback;
    List<Duration> steps(String key, List<Duration> fallback) {
      final raw = map[key];
      if (raw is! List) return fallback;
      return [
        for (final seconds in raw)
          if (seconds is num && seconds > 0) Duration(seconds: seconds.toInt()),
      ];
    }

    return SrsSettings(
      newCardsPerDay: integer('newCardsPerDay', d.newCardsPerDay),
      maximumReviewsPerDay: integer(
        'maximumReviewsPerDay',
        d.maximumReviewsPerDay,
      ),
      learningSteps: steps('learningSteps', d.learningSteps),
      relearningSteps: steps('relearningSteps', d.relearningSteps),
      graduatingIntervalDays: integer(
        'graduatingIntervalDays',
        d.graduatingIntervalDays,
      ),
      easyIntervalDays: integer('easyIntervalDays', d.easyIntervalDays),
      startingEase: decimal('startingEase', d.startingEase),
      easyBonus: decimal('easyBonus', d.easyBonus),
      hardIntervalMultiplier: decimal(
        'hardIntervalMultiplier',
        d.hardIntervalMultiplier,
      ),
      intervalModifier: decimal('intervalModifier', d.intervalModifier),
      maximumIntervalDays: integer(
        'maximumIntervalDays',
        d.maximumIntervalDays,
      ),
      lapseIntervalFactor: decimal(
        'lapseIntervalFactor',
        d.lapseIntervalFactor,
      ),
    );
  }
}
