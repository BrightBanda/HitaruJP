import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/immersion/domain/immersion_session.dart';
import 'package:ingrain/features/sentence_mining/domain/sentence_item.dart';
import 'package:ingrain/features/srs/domain/review_event.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_item.dart';

/// The guided first lesson's session id (see `FirstLessonView`).
const firstLessonSourceId = 'dialogue:first-lesson';

/// A reading session at least this long counts as a dialogue read.
const _dialogueReadSeconds = 60;

/// Turns what the app already records (sessions, saved words and sentences,
/// flashcard reviews) into one [DayActivity] per day, for XP.
///
/// XP is derived rather than stored as its own ledger: nothing can be counted
/// twice, and retuned rules apply to everyone's history alike. Like the
/// progress figures, each item belongs to the local day it started on.
List<DayActivity> dayActivitiesFrom({
  required List<ImmersionSession> sessions,
  required List<SentenceItem> sentences,
  required List<VocabularyItem> vocabulary,
  required List<ReviewEvent> reviewEvents,
}) {
  final days = <DateTime, _Day>{};
  _Day on(DateTime time) =>
      days.putIfAbsent(DateTime(time.year, time.month, time.day), _Day.new);

  // Oldest first, so the first lesson is credited once, on the day it was
  // first finished.
  final ordered = [...sessions]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  var lessonCredited = false;
  for (final session in ordered) {
    final seconds = session.durationSeconds;
    if (seconds <= 0) continue;
    final day = on(session.startedAt);
    day.total += seconds;
    switch (session.activityType) {
      case ActivityType.watching || ActivityType.listening:
        day.watch += seconds;
      case ActivityType.reading:
        day.read += seconds;
        if (session.sourceId == firstLessonSourceId) {
          if (!lessonCredited) day.firstLesson = true;
          lessonCredited = true;
        } else if (seconds >= _dialogueReadSeconds &&
            session.sourceId.startsWith('dialogue:')) {
          day.dialogues.add(session.sourceId);
        }
      case ActivityType.speaking || ActivityType.reviewing:
        break;
    }
  }
  for (final sentence in sentences) {
    on(sentence.createdAt).sentences++;
  }
  for (final word in vocabulary) {
    on(word.createdAt).words++;
  }
  for (final review in reviewEvents) {
    on(review.reviewedAt).reviews++;
  }

  return [
    for (final MapEntry(key: day, value: d) in days.entries)
      DayActivity(
        day: day,
        watchSeconds: d.watch,
        readSeconds: d.read,
        totalSeconds: d.total,
        dialoguesRead: d.dialogues.length,
        sentencesMined: d.sentences,
        wordsSaved: d.words,
        reviews: d.reviews,
        firstLesson: d.firstLesson,
      ),
  ];
}

class _Day {
  int watch = 0;
  int read = 0;
  int total = 0;
  final Set<String> dialogues = {};
  int sentences = 0;
  int words = 0;
  int reviews = 0;
  bool firstLesson = false;
}
