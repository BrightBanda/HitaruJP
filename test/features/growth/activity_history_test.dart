import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/growth/data/activity_history.dart';
import 'package:ingrain/features/immersion/domain/immersion_session.dart';
import 'package:ingrain/features/sentence_mining/domain/sentence_item.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/domain/review_event.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_item.dart';

void main() {
  final monday = DateTime(2026, 10, 19, 9);
  final tuesday = DateTime(2026, 10, 20, 21);

  ImmersionSession session(
    String source,
    ActivityType type,
    int seconds, {
    DateTime? at,
  }) => ImmersionSession(
    id: '$source-${at ?? monday}',
    uid: 'u1',
    sourceId: source,
    activityType: type,
    startedAt: at ?? monday,
    durationSeconds: seconds,
  );

  test('history becomes one activity record per day', () {
    final days = dayActivitiesFrom(
      sessions: [
        session('video:a', ActivityType.watching, 600),
        session('dialogue:cafe', ActivityType.reading, 120),
        session('dialogue:short', ActivityType.reading, 20),
        session('deck', ActivityType.reviewing, 300),
        session('video:b', ActivityType.listening, 60, at: tuesday),
      ],
      sentences: [
        SentenceItem(
          id: 's1',
          uid: 'u1',
          japanese: '猫が好き',
          sourceType: SourceType.youtube,
          sourceId: 'a',
          createdAt: monday,
        ),
      ],
      vocabulary: [
        for (final w in ['猫', '犬'])
          VocabularyItem(
            id: w,
            uid: 'u1',
            word: w,
            sourceType: SourceType.youtube,
            sourceId: 'a',
            createdAt: tuesday,
            updatedAt: tuesday,
          ),
      ],
      reviewEvents: [
        ReviewEvent(
          id: 'r1',
          uid: 'u1',
          cardId: 'c',
          cardType: CardType.vocabulary,
          rating: Rating.good,
          reviewedAt: monday,
          intervalDaysAfter: 1,
        ),
      ],
    )..sort((a, b) => a.day.compareTo(b.day));

    expect(days, hasLength(2));
    final mon = days.first;
    expect(mon.day, DateTime(2026, 10, 19));
    expect(mon.watchSeconds, 600);
    expect(mon.readSeconds, 140);
    expect(mon.totalSeconds, 1040, reason: 'flashcard time counts too');
    expect(mon.dialoguesRead, 1, reason: 'a 20-second glance is not a read');
    expect(mon.sentencesMined, 1);
    expect(mon.reviews, 1);
    expect(days.last.wordsSaved, 2);
    expect(days.last.watchSeconds, 60, reason: 'listening counts as watching');
  });

  test('the first lesson is credited once, and not as a dialogue', () {
    final days = dayActivitiesFrom(
      sessions: [
        session(firstLessonSourceId, ActivityType.reading, 90),
        session(firstLessonSourceId, ActivityType.reading, 90, at: tuesday),
      ],
      sentences: const [],
      vocabulary: const [],
      reviewEvents: const [],
    )..sort((a, b) => a.day.compareTo(b.day));

    expect(days.first.firstLesson, isTrue);
    expect(days.first.dialoguesRead, 0);
    expect(days.last.firstLesson, isFalse, reason: 'a replay earns nothing');
  });
}
