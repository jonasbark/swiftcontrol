// The app-picker tiles must be pixel-identical in size: the visible card
// (SelectableCard's inner Button) has to fill its uniform GridView cell
// instead of shrink-wrapping its caption (1-line vs 2-line captions and the
// selected state previously produced uneven tiles).
import 'package:bike_control/pages/onboarding/steps/step_app.dart' show OnboardingAppTile, onboardingAppBody;
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'widget_snapshot.dart';

Future<void> main() async {
  await ensureSnapshotHarness();

  Future<void> expectUniformTiles(WidgetTester tester, {required double width}) async {
    await captureWidget(
      tester,
      name: 'onboarding_step_app_uniform_$width',
      width: width,
      builder: (c) => onboardingAppBody(
        c,
        selected: SupportedApp.supportedApps.first,
        onSelect: (_) {},
      ),
    );

    final cards = find.byType(OnboardingAppTile);
    expect(cards, findsWidgets);
    final sizes = <Size>{};
    for (final card in cards.evaluate()) {
      sizes.add(tester.getSize(find.byWidget(card.widget)));
    }
    expect(sizes, hasLength(1),
        reason: 'visible tile cards must all be the same size at width $width, got: $sizes');
  }

  testWidgets('app grid tiles are uniform (3 columns)', (tester) async {
    await expectUniformTiles(tester, width: 380);
  });

  testWidgets('app grid tiles are uniform (5 columns)', (tester) async {
    await expectUniformTiles(tester, width: 640);
  });
}
