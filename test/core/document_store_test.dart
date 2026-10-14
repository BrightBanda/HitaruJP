import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/storage/firestore_document_store.dart';
import 'package:ingrain/features/content/data/local_content_repository.dart';

void main() {
  group('documentPath', () {
    test('nests uid and collection under users/', () {
      expect(
        documentPath('user-1', 'vocabulary', 'abc-123'),
        'users/user-1/vocabulary/abc-123',
      );
    });

    test('keeps ids Firestore can address', () {
      final path = documentPath('user-1', 'sentences', 'm3k9-x1f');
      expect(path.split('/'), ['users', 'user-1', 'sentences', 'm3k9-x1f']);
      // A slash anywhere but the first three positions would change the shape.
      expect('/'.allMatches(path).length, 3);
    });

    test(
      'the composite transcript id stays one document in contentHistory',
      () {
        final docId = LocalContentRepository.transcriptDocId('dQw4w9WgXcQ');
        expect(docId, 'dQw4w9WgXcQ__transcript');
        expect(
          documentPath('user-1', 'contentHistory', docId),
          'users/user-1/contentHistory/dQw4w9WgXcQ__transcript',
        );
        expect('/'.allMatches(docId).length, 0);
      },
    );

    test('distinct content ids cannot collide on one transcript document', () {
      expect(
        LocalContentRepository.transcriptDocId('a__transcript'),
        isNot(LocalContentRepository.transcriptDocId('a')),
      );
    });
  });

  group('collectionPath', () {
    test('lists a whole collection for one user', () {
      expect(
        collectionPath('user-1', 'reviewCards'),
        'users/user-1/reviewCards',
      );
    });
  });

  group('assertFirestoreSafe', () {
    test('accepts the shapes the app actually persists', () {
      expect(
        () => assertFirestoreSafe({
          'id': 'abc',
          'count': 3,
          'ratio': 0.5,
          'done': false,
          'createdAt': '2026-10-05T00:00:00.000Z',
          'nested': [
            {'index': 0, 'text': '文'},
          ],
          'absent': null,
        }),
        returnsNormally,
      );
    });

    test('rejects a DateTime and names the field', () {
      expect(
        () => assertFirestoreSafe({'lastOpenedAt': DateTime(2026, 3, 15)}),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'value.lastOpenedAt')
              .having(
                (e) => e.message.toString(),
                'message',
                contains('DateTime'),
              ),
        ),
      );
    });

    test('rejects an unsupported value nested inside a list', () {
      expect(
        () => assertFirestoreSafe({
          'sentences': [
            {'startSeconds': 1},
            {'startSeconds': 'not a number', 'extra': Duration.zero},
          ],
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a non-String map key', () {
      expect(
        () => assertFirestoreSafe({1: 'one'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
