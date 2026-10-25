import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/content/domain/transcript_sentence.dart';
import 'package:ingrain/features/content/presentation/view/player/immersion_player_view.dart';
import 'package:ingrain/features/content/presentation/view/player/transcript_view.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/vocabulary/presentation/widgets/tappable_transcript_text.dart';

/// Forty three-second lines: far more than fit on screen.
final _lines = [
  for (var i = 0; i < 40; i++)
    TranscriptSentence(
      index: i,
      text: '行$i',
      startSeconds: i * 3,
      endSeconds: i * 3 + 3,
    ),
];

void main() {
  Future<ProviderContainer> pumpTranscript(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [transcriptProvider('c1').overrideWith((ref) async => _lines)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 300, child: TranscriptView(contentId: 'c1')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder nowPlaying() => find.text('Now playing');

  bool nowPlayingShown(WidgetTester tester) =>
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: nowPlaying(),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity ==
      1;

  testWidgets('scrolling away offers a way back to the playing line', (
    tester,
  ) async {
    await pumpTranscript(tester);
    expect(nowPlayingShown(tester), isFalse, reason: 'following: no button');

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(nowPlayingShown(tester), isTrue);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(
      find.text('行0'),
      findsNothing,
      reason: 'it stays where you scrolled',
    );

    await tester.tap(nowPlaying());
    await tester.pumpAndSettle();
    expect(find.text('行0'), findsOneWidget, reason: 'back at the playing line');
    expect(nowPlayingShown(tester), isFalse);
  });

  testWidgets('the list does not pull itself back while you read', (
    tester,
  ) async {
    final container = await pumpTranscript(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    // Playback moves on a few lines and time passes.
    container
        .read(playbackPositionProvider.notifier)
        .setPosition(const Duration(seconds: 7));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.text('行2'), findsNothing);
    expect(nowPlayingShown(tester), isTrue);
  });

  testWidgets('a tapped word lights up, then fades', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TappableTranscriptText(
            tokens: const ['猫', 'が', '好き'],
            onTokenTap: tapped.add,
          ),
        ),
      ),
    );

    Color? background(String word) {
      Color? found;
      tester.widget<RichText>(find.byType(RichText)).text.visitChildren((span) {
        if (span is TextSpan && span.text == word) {
          found = span.style?.backgroundColor;
        }
        return true;
      });
      return found;
    }

    TapGestureRecognizer recognizerFor(String word) {
      TapGestureRecognizer? found;
      tester.widget<RichText>(find.byType(RichText)).text.visitChildren((span) {
        if (span is TextSpan && span.text == word) {
          found = span.recognizer as TapGestureRecognizer?;
        }
        return true;
      });
      return found!;
    }

    recognizerFor('好き').onTapDown!(TapDownDetails());
    await tester.pump();
    expect(background('好き'), isNotNull, reason: 'lit while pressed');
    expect(background('猫'), isNull, reason: 'only the word under the finger');

    recognizerFor('好き').onTap!();
    await tester.pump(const Duration(milliseconds: 100));
    expect(background('好き'), isNotNull, reason: 'lingers after the tap');
    expect(tapped, ['好き']);

    await tester.pumpAndSettle();
    expect(background('好き'), isNull, reason: 'faded away');
  });
}
