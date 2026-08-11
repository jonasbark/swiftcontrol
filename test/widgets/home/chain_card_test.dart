import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/home/chain_state.dart';
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
                    onInstructions: onInstructions,
                  ),
                )
              : ChainCard(
                  link: l,
                  tile: const Icon(LucideIcons.gamepad),
                  title: l.title,
                  statusLabel: 'status',
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

  group('collapsing', () {
    testWidgets('a ready card shows only the all-done summary', (tester) async {
      await pumpCard(tester, link());

      expect(find.text(l.chainAllStepsDone(3)), findsOneWidget);
      expect(find.byType(StepRow), findsNothing);
    });

    testWidgets('an unresolved card opens itself onto its steps', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention, steps: [true, false, false]));

      expect(find.text(l.chainStepsDone(1, 3)), findsOneWidget);
      expect(find.byType(StepRow), findsNWidgets(3));
    });

    testWidgets('tapping the summary expands a ready card', (tester) async {
      await pumpCard(tester, link());

      await tester.tap(find.text(l.chainAllStepsDone(3)));
      await tester.pumpAndSettle();

      expect(find.byType(StepRow), findsNWidgets(3));
    });

    testWidgets('a card with no steps has no summary row at all', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.off, steps: []));

      expect(find.byType(StepRow), findsNothing);
      expect(find.textContaining('steps done'), findsNothing);
    });
  });

  group('the active step', () {
    testWidgets('is the first unfinished one, and the only one offering instructions', (tester) async {
      var opened = 0;
      await pumpCard(
        tester,
        link(status: LinkStatus.attention, steps: [true, false, false]),
        onInstructions: () => opened++,
      );

      final rows = tester.widgetList<StepRow>(find.byType(StepRow)).toList();
      expect(rows.map((r) => r.active), [false, true, false]);
      // Exactly one next action on the card, never two.
      expect(find.text(l.chainShowMeHow), findsOneWidget);

      await tester.tap(find.text(l.chainShowMeHow));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('is absent when every step is done', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention), onInstructions: () {});

      expect(tester.widgetList<StepRow>(find.byType(StepRow)).every((r) => !r.active), isTrue);
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
    // The summary row sits inside a Button, whose own padding used to inset it
    // past the steps below — so the checklist icon and the step ticks started
    // at different x. They are one column and must read as one.
    testWidgets('the summary icon and the step ticks share a left edge', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention, steps: [true, false]));

      final summaryIcon = find.byIcon(LucideIcons.listChecks);
      expect(summaryIcon, findsOneWidget);

      final summaryLeft = tester.getTopLeft(summaryIcon).dx;
      final ticks = find.byKey(stepTickKey);
      expect(ticks, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(tester.getTopLeft(ticks.at(i)).dx, moreOrLessEquals(summaryLeft, epsilon: 0.5));
      }
    });

    testWidgets('the summary label and the step labels share a left edge', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention, steps: [true, false]));

      final summaryLabel = tester.getTopLeft(find.text(l.chainStepsDone(1, 2))).dx;
      final stepLabel = tester.getTopLeft(find.text(l.chainStepBluetoothReady)).dx;
      expect(stepLabel, moreOrLessEquals(summaryLabel, epsilon: 0.5));
    });
  });

  group('animating a status change', () {
    testWidgets('a card that becomes ready collapses its checklist over time, not instantly', (tester) async {
      await pumpCard(tester, link(status: LinkStatus.attention, steps: [true, true, false]));
      expect(find.byType(StepRow), findsNWidgets(3));

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
}
