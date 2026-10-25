import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/storage/local_document_store.dart';

import '../../support/fake_auth_repository.dart';

import 'package:ingrain/features/content/data/local_content_repository.dart';
import 'package:ingrain/features/content/domain/transcript_sentence.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LocalDocumentStore store;
  late LocalContentRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = LocalDocumentStore(prefs);
    final auth = FakeAuthRepository();
    repository = LocalContentRepository(store, auth);
  });

  group('LocalContentRepository', () {
    test('saves the playback position for next time', () async {
      await repository.create(
        sourceUrl: 'https://www.youtube.com/watch?v=aaaaaaaaaa1',
        title: 'First',
      );
      await repository.updateLastPosition('aaaaaaaaaa1', 142);

      final item = await repository.getContent('aaaaaaaaaa1');
      expect(item.lastPositionSeconds, 142);
    });

    test('saving a position does not bring back a deleted video', () async {
      await repository.updateLastPosition('zzzzzzzzzz9', 30);

      expect(await repository.watchAll().first, isEmpty);
    });

    test(
      'lists the video added last first, even if an older one was opened since',
      () async {
        await repository.create(
          sourceUrl: 'https://www.youtube.com/watch?v=aaaaaaaaaa1',
          title: 'First',
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await repository.create(
          sourceUrl: 'https://www.youtube.com/watch?v=bbbbbbbbbb2',
          title: 'Second',
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        // Opening the first one again must not lift it above the newer video.
        await repository.updateLastPosition('aaaaaaaaaa1', 30);

        final titles = (await repository.watchAll().first).map((i) => i.title);

        expect(titles, ['Second', 'First']);
      },
    );

    test('extracts video ID correctly from standard YouTube URL', () async {
      final item = await repository.create(
        sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'Rickroll',
      );
      expect(item.id, 'dQw4w9WgXcQ');
    });

    test('extracts video ID from mobile share URL with tracking parameter before v', () async {
      final item = await repository.create(
        sourceUrl:
            'https://www.youtube.com/watch?si=1234567890123456&v=dQw4w9WgXcQ',
        title: 'Rickroll Mobile',
      );
      expect(item.id, 'dQw4w9WgXcQ');
    });

    test(
      'extracts video ID from youtu.be link with tracking parameter',
      () async {
        final item = await repository.create(
          sourceUrl: 'https://youtu.be/dQw4w9WgXcQ?si=abcdefghijklmnop',
          title: 'Rickroll Shortlink',
        );
        expect(item.id, 'dQw4w9WgXcQ');
      },
    );

    test('extracts video ID from mobile live stream URL', () async {
      final item = await repository.create(
        sourceUrl: 'https://www.youtube.com/live/dQw4w9WgXcQ?feature=share',
        title: 'Live Stream',
      );
      expect(item.id, 'dQw4w9WgXcQ');
    });

    test(
      'watchAll skips transcript documents in the same collection',
      () async {
        await repository.create(
          sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          title: 'With transcript',
        );
        await repository.saveTranscript('dQw4w9WgXcQ', const [
          TranscriptSentence(
            index: 0,
            text: 'こんにちは',
            startSeconds: 0,
            endSeconds: 2,
          ),
        ]);

        final items = await repository.watchAll().first;

        expect(items.map((item) => item.id), ['dQw4w9WgXcQ']);
        expect(await repository.getTranscript('dQw4w9WgXcQ'), hasLength(1));
      },
    );

    test('extracts video ID from bare video ID', () async {
      final item = await repository.create(
        sourceUrl: 'dQw4w9WgXcQ',
        title: 'Bare ID',
      );
      expect(item.id, 'dQw4w9WgXcQ');
    });
  });
}
