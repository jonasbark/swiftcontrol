import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/home/chain_state.dart';
import 'package:bike_control/widgets/home/ampel.dart';
import 'package:bike_control/widgets/home/chain_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

ChainLink link({
  LinkStatus status = LinkStatus.ready,
  List<bool> steps = const [true, true, true],
  bool optional = false,
  bool dismissible = false,
}) {
  return ChainLink(
    key: ChainLinkKey.controller,
    id: 'controller:test',
    status: status,
    title: 'Zwift Click V2',
    optional: optional,
    dismissible: dismissible,
    deviceId: 'test',
    steps: [
      for (final (i, done) in steps.indexed)
        SetupStep(
          id: [
            SetupStepId.controllerBluetoothReady,
            SetupStepId.controllerPaired,
            SetupStepId.controllerButtonsMapped,
            SetupStepId.controllerInRange,
          ][i % 4],
          done: done,
        ),
    ],
  );
}

Future<void> pumpCard(
  WidgetTester tester,
  ChainLink l, {
  VoidCallback? onInstructions,
  VoidCallback? onDismissed,
  List<Widget> statusBadges = const [],
}) async {
  await tester.pumpWidget(
    ShadcnApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      theme: ThemeData(colorScheme: ColorSchemes.lightSlate, radius: 0.5),
      home: Scaffold(
        child: SingleChildScrollView(
          child: l.dismissible
              ? Dismissible(
                  key: const ValueKey('dismiss'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => onDismissed?.call(),
                  child: ChainCard(
                    link: l,
                    tile: const Icon(LucideIcons.gamepad),
                    title: l.title,
                    statusLabel: 'status',
                    statusBadges: statusBadges,
                    onInstructions: onInstructions,
                  ),
                )
              : ChainCard(
                  link: l,
                  tile: const Icon(LucideIcons.gamepad),
                  title: l.title,
                  statusLabel: 'status',
                  statusBadges: statusBadges,
                  onInstructions: onInstructions,
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() async {
  await AppLocalizations.load(const Locale('en'));
  final l = AppLocalizations();

  group('only outstanding steps are shown', () {
    testWidgets('a finished card shows no checklist at all', (tester) async {
      await pumpCard(tester, link());

      expect(find.byType(StepRow), findsNothing);
      // No summary, no counter, no way to unfold a list of ticked boxes.
      expect(find.textContaining('steps done'), findsNothing);
      expect(find.byIcon(LucideIcons.chevronDown), findsNothing);
      expect(find.byIcon(LucideIcons.chevronUp), findsNothing);
    });

    testWidgets('only the pending steps are rendered', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention, steps: [true, false, false]));

      expect(find.byType(StepRow), findsNWidgets(2));
      // The two that are done have nothing left to say.
      expect(find.text(l.chainStepBluetoothReady), findsNothing);
    });

    testWidgets('a card with no steps renders no checklist', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.off, steps: []));
      expect(find.byType(StepRow), findsNothing);
    });

    testWidgets('every rendered step is genuinely outstanding', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention, steps: [false, true, false, true]));

      final rows = tester.widgetList<StepRow>(find.byType(StepRow)).toList();
      expect(rows, hasLength(2));
      expect(rows.every((r) => !r.step.done), isTrue);
    });
  });

  group('the active step', () {
    testWidgets('is the first outstanding one, and the only one offering instructions', (tester) async {
      var opened = 0;
      await pumpCard(
        tester,
        link(status: LinkStatus.attention, steps: [true, false, false]),
        onInstructions: () => opened++,
      );

      final rows = tester.widgetList<StepRow>(find.byType(StepRow)).toList();
      expect(rows.map((r) => r.active), [true, false]);
      // Exactly one next action on the card, never two.
      expect(find.text(l.chainShowMeHow), findsOneWidget);

      await tester.tap(find.text(l.chainShowMeHow));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('offers nothing when every step is done', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention), onInstructions: () {});
      expect(find.text(l.chainShowMeHow), findsNothing);
    });
  });

  testWidgets('an optional card is tagged as such', (tester) async {
    await pumpCard(tester, link(status: LinkStatus.off, optional: true, steps: []));
    expect(find.text(l.chainOptional.toUpperCase()), findsOneWidget);
  });

  testWidgets('a required card carries no optional tag', (tester) async {
    await pumpCard(tester, link());
    expect(find.text(l.chainOptional.toUpperCase()), findsNothing);
  });

  group('alignment', () {
    testWidgets('every step tick shares one left edge', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention, steps: [false, false, false]));

      final ticks = find.byKey(stepTickKey);
      expect(ticks, findsNWidgets(3));
      final first = tester.getTopLeft(ticks.at(0)).dx;
      for (var i = 1; i < 3; i++) {
        expect(tester.getTopLeft(ticks.at(i)).dx, moreOrLessEquals(first, epsilon: 0.5));
      }
    });

    testWidgets('every step label shares one left edge', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention, steps: [false, false]));

      final a = tester.getTopLeft(find.text(l.chainStepBluetoothReadyPending)).dx;
      final b = tester.getTopLeft(find.text(l.chainStepControllerPairedPending)).dx;
      expect(b, moreOrLessEquals(a, epsilon: 0.5));
    });
  });

  group('animating a status change', () {
    testWidgets('a card that becomes ready collapses its checklist over time, not instantly', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention, steps: [true, true, false]));
      // Two done, one outstanding — only the outstanding one is on screen.
      expect(find.byType(StepRow), findsOneWidget);

      // The last step lands: the card is now ready and should fold away.
      await tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          theme: ThemeData(colorScheme: ColorSchemes.lightSlate, radius: 0.5),
          home: Scaffold(
            child: SingleChildScrollView(
              child: ChainCard(
                link: link(),
                tile: const Icon(LucideIcons.gamepad),
                title: 'Zwift Click V2',
                statusLabel: 'status',
              ),
            ),
          ),
        ),
      );

      // Mid-flight the card is still taller than its resting height — proof the
      // collapse is animating rather than snapping shut in one frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final midHeight = tester.getSize(find.byType(ChainCard)).height;

      await tester.pumpAndSettle();
      final restHeight = tester.getSize(find.byType(ChainCard)).height;

      expect(midHeight, greaterThan(restHeight));
      expect(find.byType(StepRow), findsNothing);
    });
  });

  group('swipe to forget', () {
    testWidgets('a disconnected card can be swiped away', (tester) async {
      var dismissed = 0;
      await pumpCard(
        tester,
        link(status: LinkStatus.attention, steps: [true, true, false], dismissible: true),
        onDismissed: () => dismissed++,
      );

      await tester.drag(find.byType(ChainCard), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(dismissed, 1);
    });

    testWidgets('a connected card has no dismiss gesture wrapped around it', (tester) async {
      await pumpCard(tester, link());
      expect(find.byType(Dismissible), findsNothing);
    });
  });

  // Battery / firmware / signal warnings ride beside the status rather than in
  // the body: they qualify "Connected" — it works, but not for much longer.
  testWidgets('status badges render beside the status label', (tester) async {
    await pumpCard(
      tester,
      link(),
      statusBadges: const [Icon(LucideIcons.batteryWarning, key: ValueKey('badge-battery'))],
    );

    expect(find.byKey(const ValueKey('badge-battery')), findsOneWidget);
    expect(
      find.ancestor(of: find.byKey(const ValueKey('badge-battery')), matching: find.byType(StatusLine)),
      findsOneWidget,
    );
  });

  testWidgets('a healthy card carries no badges', (tester) async {
    await pumpCard(tester, link());

    expect(find.byKey(const ValueKey('badge-battery')), findsNothing);
  });
}
