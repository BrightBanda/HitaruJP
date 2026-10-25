import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/player_host/player_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_overrides.dart';

ContentItem _video({int position = 0, int? length = 600}) => ContentItem(
  id: 'abcDEF12345',
  sourceType: SourceType.youtube,
  sourceUrl: 'https://www.youtube.com/watch?v=abcDEF12345',
  title: '日本語 vlog',
  lastPositionSeconds: position,
  durationSeconds: length,
  lastOpenedAt: DateTime(2026, 10, 1),
);

void main() {
  late PlayerHost host;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: appTestOverrides(await SharedPreferences.getInstance()),
    );
    addTearDown(container.dispose);
    container.read(playerHostProvider);
    host = container.read(playerHostProvider.notifier);
  });

  test('continues from the saved position', () {
    expect(
      host.resumePositionFor(_video(position: 222)),
      const Duration(seconds: 222),
    );
  });

  test('starts over when barely started', () {
    expect(host.resumePositionFor(_video(position: 3)), isNull);
  });

  test('starts over when it was watched to the end', () {
    expect(host.resumePositionFor(_video(position: 595)), isNull);
  });

  test('a video of unknown length still continues', () {
    expect(
      host.resumePositionFor(_video(position: 90, length: null)),
      const Duration(seconds: 90),
    );
  });
}
