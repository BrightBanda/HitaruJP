import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/ads/domain/ad_creative.dart';
import 'package:ingrain/features/ads/presentation/ad_card.dart';
import 'package:ingrain/features/ads/presentation/ad_providers.dart';

Future<void> pump(WidgetTester tester, {required bool showAds}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [showAdsProvider.overrideWithValue(showAds)],
      child: const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AdCard(placement: AdPlacement.playerList),
              // The shelf gives it a fixed height.
              SizedBox(
                height: 140,
                child: AdCard(placement: AdPlacement.homeShelf, compact: true),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the free tier sees ads, labelled as ads', (tester) async {
    await pump(tester, showAds: true);

    expect(find.text('Ad'), findsNWidgets(2));
    expect(find.text('Go Premium'), findsOneWidget);
  });

  testWidgets('paying learners see no ads', (tester) async {
    await pump(tester, showAds: false);

    expect(find.text('Ad'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  test('every placement gets an ad and the home ones rotate with the seed', () {
    const source = HouseAdSource();
    for (final placement in AdPlacement.values) {
      expect(source.next(placement), isNotNull);
    }
    expect(
      source.next(AdPlacement.homeShelf, seed: 0).id,
      isNot(source.next(AdPlacement.homeShelf, seed: 1).id),
    );
  });
}
