import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/proxy_device_details/metric_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The tile itself — presentational only, and deliberately dumb: it renders
/// whatever [MetricSourceOption]s it is given as an inline vertical list,
/// never a toggle, a dropdown, or a picker sheet. `live_metrics_section_test
/// .dart` covers deciding WHICH options exist and what their state (and
/// subtitle) resolves to (including the connect/disconnect ordering); this
/// file covers HOW [MetricCard] renders a given list, including the
/// side-by-side/stacked layout switch.
Future<void> main() async {
  await AppLocalizations.load(const Locale('en'));

  /// Two cards side by side inside a [width]-wide harness — exactly how
  /// `LiveMetricsSection` lays the grid out (`Row(children: [cardA, cardB])`
  /// inside a column of that width) — rather than one card alone with
  /// unconstrained width, which would hide a truncation/overflow bug that
  /// only shows up once the tile is actually half-width.
  ///
  /// [width] defaults to a realistic PHONE width (360, matching this
  /// section's own signals-grid usage) — each card lands well under
  /// `MetricCard._sideBySideBreakpoint`'s 240px content-width threshold, so
  /// the source list (when present) stacks below the value. Passing a wider
  /// [width] (see the "layout: side-by-side vs stacked" group) pushes each
  /// card's content width above that threshold instead.
  Future<void> pump(WidgetTester tester, MetricCard card, {MetricCard? second, double width = 360}) async {
    // A `SizedBox(width: ...)` alone can't narrow anything here: `Scaffold`
    // gives its child TIGHT constraints matching the (default 800×600) test
    // surface, and a tight incoming constraint always wins over a `SizedBox`'s
    // own requested width (`BoxConstraints.enforce`) — so the actual surface
    // size has to change for [width] to mean anything. Matches the idiom
    // `network_troubleshooting_layout_test.dart` already uses for the same
    // reason.
    final size = Size(width, 800);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: ShadcnApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Scaffold(
            child: Row(children: [card, second ?? const _FillerCard()]),
          ),
        ),
      ),
    );
  }

  Color? dotColor(WidgetTester tester, String id) {
    final container = tester.widget<Container>(find.byKey(Key('metric-card-source-dot-$id')));
    return (container.decoration as BoxDecoration?)?.color;
  }

  MetricSourceOption option({
    required String id,
    required String label,
    String? subtitle,
    required MetricSourceState state,
    bool selected = false,
    Future<void> Function()? onSelect,
    Future<void> Function()? onDisconnect,
  }) => MetricSourceOption(
    id: id,
    label: label,
    subtitle: subtitle ?? 'subtitle for $id',
    state: state,
    selected: selected,
    onSelect: onSelect ?? () async {},
    onDisconnect: onDisconnect,
  );

  const baseCard = MetricCard(
    icon: LucideIcons.heart,
    iconColor: Color(0xFFEF4444),
    label: 'HEART',
    value: '142',
    unit: 'bpm',
  );

  group('THE INVARIANT: no sources', () {
    testWidgets('null sources renders label, value and unit with no control at all', (tester) async {
      await pump(tester, baseCard);

      expect(find.text('HEART'), findsOneWidget);
      expect(find.text('142'), findsOneWidget);
      expect(find.text('bpm'), findsOneWidget);
      expect(find.byKey(const Key('metric-card-source-control')), findsNothing);
    });

    testWidgets('an empty source list also renders no control', (tester) async {
      await pump(
        tester,
        MetricCard(
          icon: baseCard.icon,
          iconColor: baseCard.iconColor,
          label: baseCard.label,
          value: baseCard.value,
          unit: baseCard.unit,
          sources: const [],
        ),
      );

      expect(find.byKey(const Key('metric-card-source-control')), findsNothing);
    });

    testWidgets('a single-entry list (nothing to choose between) also renders no control', (tester) async {
      // A rider with no external sensors must see the tile exactly as it
      // renders with null/empty sources — a list of just "Trainer" would be
      // an affordance with nothing behind it.
      await pump(
        tester,
        MetricCard(
          icon: baseCard.icon,
          iconColor: baseCard.iconColor,
          label: baseCard.label,
          value: baseCard.value,
          unit: baseCard.unit,
          sources: [option(id: 'trainer', label: 'Trainer', state: MetricSourceState.trainer, selected: true)],
        ),
      );

      expect(find.byKey(const Key('metric-card-source-control')), findsNothing);
      expect(find.byKey(const Key('metric-card-source-option-trainer')), findsNothing);
    });

    testWidgets('a null value renders the unchanged "--" placeholder, still no control', (tester) async {
      await pump(
        tester,
        const MetricCard(
          key: Key('under-test'),
          icon: LucideIcons.heart,
          iconColor: Color(0xFFEF4444),
          label: 'HEART',
          value: null,
          unit: 'bpm',
        ),
      );

      // The filler card is also valueless ("--" is its own unchanged
      // placeholder too), so this scopes to the tile under test rather than
      // asserting a global count that would pass for the wrong reason.
      expect(
        find.descendant(of: find.byKey(const Key('under-test')), matching: find.text('--')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('metric-card-source-control')), findsNothing);
    });
  });

  group('sources render as a list, not a toggle', () {
    testWidgets('Trainer plus every source render as their own row, each with its own subtitle', (tester) async {
      await pump(
        tester,
        MetricCard(
          icon: baseCard.icon,
          iconColor: baseCard.iconColor,
          label: baseCard.label,
          value: baseCard.value,
          unit: baseCard.unit,
          sources: [
            option(
              id: 'trainer',
              label: 'Trainer',
              subtitle: "The trainer's own built-in reading.",
              state: MetricSourceState.trainer,
              selected: true,
            ),
            option(
              id: 'hr-1',
              label: 'HR6 0050789',
              subtitle: 'Connected — streaming its own reading.',
              state: MetricSourceState.connected,
            ),
            option(
              id: 'hr-2',
              label: 'TICKR 1234',
              subtitle: 'Not connected yet — tap to connect and use it here.',
              state: MetricSourceState.notConnected,
            ),
          ],
        ),
      );

      // All three are on screen simultaneously — no sheet, no dropdown, no
      // opening interaction needed to see them — each with its own title...
      expect(find.text('Trainer'), findsOneWidget);
      expect(find.text('HR6 0050789'), findsOneWidget);
      expect(find.text('TICKR 1234'), findsOneWidget);
      // ...and its own subtitle, distinguishable from the others.
      expect(find.text("The trainer's own built-in reading."), findsOneWidget);
      expect(find.text('Connected — streaming its own reading.'), findsOneWidget);
      expect(find.text('Not connected yet — tap to connect and use it here.'), findsOneWidget);

      // Trainer is the first row in source order (stacked at this width —
      // see the layout group below for the side-by-side case).
      expect(
        tester.getTopLeft(find.byKey(const Key('metric-card-source-option-trainer'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('metric-card-source-option-hr-1'))).dy),
      );
    });

    testWidgets('tapping a row invokes its own onSelect, not a shared handler', (tester) async {
      var trainerTapped = false;
      var sensorTapped = false;
      await pump(
        tester,
        MetricCard(
          icon: baseCard.icon,
          iconColor: baseCard.iconColor,
          label: baseCard.label,
          value: baseCard.value,
          unit: baseCard.unit,
          sources: [
            option(
              id: 'trainer',
              label: 'Trainer',
              state: MetricSourceState.trainer,
              selected: true,
              onSelect: () async => trainerTapped = true,
            ),
            option(
              id: 'hr-1',
              label: 'HR6 0050789',
              state: MetricSourceState.notConnected,
              onSelect: () async => sensorTapped = true,
            ),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('metric-card-source-option-hr-1')));
      await tester.pumpAndSettle();

      expect(sensorTapped, isTrue);
      expect(trainerTapped, isFalse);
    });
  });

  group('the selected row is clearly marked', () {
    testWidgets('the selected row shows a check mark; unselected rows do not', (tester) async {
      await pump(
        tester,
        MetricCard(
          icon: baseCard.icon,
          iconColor: baseCard.iconColor,
          label: baseCard.label,
          value: baseCard.value,
          unit: baseCard.unit,
          sources: [
            option(id: 'trainer', label: 'Trainer', state: MetricSourceState.trainer),
            option(id: 'hr-1', label: 'HR6 0050789', state: MetricSourceState.connected, selected: true),
          ],
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('metric-card-source-option-hr-1')),
          matching: find.byIcon(LucideIcons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('metric-card-source-option-trainer')),
          matching: find.byIcon(LucideIcons.check),
        ),
        findsNothing,
      );

      // Its `SelectedButton` also carries `value: true` — the row's own
      // (already-subtle) background tint, on top of the check mark.
      final selectedButton = tester.widget<SelectedButton>(find.byKey(const Key('metric-card-source-option-hr-1')));
      expect(selectedButton.value, isTrue);
    });
  });

  group('per-source dot state is distinguishable', () {
    testWidgets('trainer, connected, connecting, waiting, lost and not-connected all render their own colour', (
      tester,
    ) async {
      await pump(
        tester,
        MetricCard(
          icon: baseCard.icon,
          iconColor: baseCard.iconColor,
          label: baseCard.label,
          value: baseCard.value,
          unit: baseCard.unit,
          sources: [
            option(id: 'trainer', label: 'Trainer', state: MetricSourceState.trainer, selected: true),
            option(id: 'a', label: 'A', state: MetricSourceState.connected),
            option(id: 'b', label: 'B', state: MetricSourceState.connecting),
            option(id: 'c', label: 'C', state: MetricSourceState.waitingForFirstReading),
            option(id: 'd', label: 'D', state: MetricSourceState.lost),
            option(id: 'e', label: 'E', state: MetricSourceState.notConnected),
          ],
        ),
      );

      final cs = Theme.of(tester.element(find.byType(MetricCard).first)).colorScheme;
      expect(dotColor(tester, 'trainer'), cs.mutedForeground);
      expect(dotColor(tester, 'a'), const Color(0xFF22C55E));
      expect(dotColor(tester, 'b'), const Color(0xFFF59E0B));
      expect(dotColor(tester, 'c'), const Color(0xFFF59E0B));
      expect(dotColor(tester, 'd'), const Color(0xFFEF4444));
      expect(dotColor(tester, 'e'), cs.mutedForeground);

      // Distinguishable from one another: connected/lost read as visibly
      // different colours side by side in the same tile, not just "not
      // muted".
      expect(dotColor(tester, 'a'), isNot(dotColor(tester, 'd')));
    });
  });

  testWidgets('hierarchy: every row label stays muted foreground, selected or not — only the dot/check carry state', (
    tester,
  ) async {
    await pump(
      tester,
      MetricCard(
        icon: baseCard.icon,
        iconColor: baseCard.iconColor,
        label: baseCard.label,
        value: baseCard.value,
        unit: baseCard.unit,
        sources: [
          option(id: 'trainer', label: 'Trainer', state: MetricSourceState.trainer),
          option(id: 'hr-1', label: 'HR6 0050789', state: MetricSourceState.lost, selected: true),
        ],
      ),
    );

    final cs = Theme.of(tester.element(find.byType(MetricCard).first)).colorScheme;
    final unselected = tester.widget<Text>(find.text('Trainer'));
    final selected = tester.widget<Text>(find.text('HR6 0050789'));
    expect(unselected.style?.color, cs.mutedForeground);
    expect(selected.style?.color, cs.mutedForeground);
    // Small — well below the 28px hero value — so the control cannot
    // out-shout the number above it.
    expect(unselected.style?.fontSize, lessThan(16));
    expect(selected.style?.fontSize, lessThan(16));
  });

  testWidgets('a long source name truncates instead of overflowing a half-width tile', (tester) async {
    await pump(
      tester,
      MetricCard(
        icon: baseCard.icon,
        iconColor: baseCard.iconColor,
        label: baseCard.label,
        value: baseCard.value,
        unit: baseCard.unit,
        sources: [
          option(id: 'trainer', label: 'Trainer', state: MetricSourceState.trainer, selected: true),
          option(
            id: 'long',
            label: 'A Very Long Sensor Display Name That Would Never Fit',
            state: MetricSourceState.notConnected,
          ),
        ],
      ),
    );
    await tester.pump();

    // No RenderFlex/layout overflow exception was thrown during the pump
    // above at this constrained (half-tile) width.
    expect(tester.takeException(), isNull);

    final text = tester.widget<Text>(find.text('A Very Long Sensor Display Name That Would Never Fit'));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('long-press on a row invokes onDisconnect when set', (tester) async {
    var disconnected = false;
    await pump(
      tester,
      MetricCard(
        icon: baseCard.icon,
        iconColor: baseCard.iconColor,
        label: baseCard.label,
        value: baseCard.value,
        unit: baseCard.unit,
        sources: [
          option(id: 'trainer', label: 'Trainer', state: MetricSourceState.trainer),
          option(
            id: 'hr-1',
            label: 'HR6 0050789',
            state: MetricSourceState.connected,
            selected: true,
            onDisconnect: () async => disconnected = true,
          ),
        ],
      ),
    );

    await tester.longPress(find.byKey(const Key('metric-card-source-option-hr-1')));
    await tester.pumpAndSettle();

    expect(disconnected, isTrue);
  });

  testWidgets('a row with no onDisconnect ignores long-press (Trainer, or an unselected sensor)', (tester) async {
    await pump(
      tester,
      MetricCard(
        icon: baseCard.icon,
        iconColor: baseCard.iconColor,
        label: baseCard.label,
        value: baseCard.value,
        unit: baseCard.unit,
        sources: [
          option(id: 'trainer', label: 'Trainer', state: MetricSourceState.trainer, selected: true),
          option(id: 'hr-1', label: 'HR6 0050789', state: MetricSourceState.notConnected),
        ],
      ),
    );

    // Must not throw for lack of a handler.
    await tester.longPress(find.byKey(const Key('metric-card-source-option-trainer')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('layout: side-by-side vs stacked', () {
    final sources = [
      option(id: 'trainer', label: 'Trainer', state: MetricSourceState.trainer, selected: true),
      option(id: 'hr-1', label: 'HR6 0050789', state: MetricSourceState.notConnected),
    ];

    testWidgets('narrow (phone-width) card: the list stacks BELOW the value', (tester) async {
      await pump(
        tester,
        MetricCard(
          icon: baseCard.icon,
          iconColor: baseCard.iconColor,
          label: baseCard.label,
          value: baseCard.value,
          unit: baseCard.unit,
          sources: sources,
        ),
        // Default 360px harness — each card lands at ~180px raw / ~152px
        // content, well under the 240px side-by-side breakpoint.
      );

      final valueTop = tester.getTopLeft(find.text('142'));
      final listTop = tester.getTopLeft(find.byKey(const Key('metric-card-source-option-trainer')));
      expect(listTop.dy, greaterThan(valueTop.dy));
    });

    testWidgets('wide (desktop-grid-width) card: the list sits to the RIGHT of the value', (tester) async {
      await pump(
        tester,
        MetricCard(
          icon: baseCard.icon,
          iconColor: baseCard.iconColor,
          label: baseCard.label,
          value: baseCard.value,
          unit: baseCard.unit,
          sources: sources,
        ),
        // 900px harness — each card lands at ~450px raw / ~422px content,
        // comfortably over the 240px breakpoint (see
        // `MetricCard._sideBySideBreakpoint`'s own doc comment for how that
        // number was measured against the real signals-grid layout).
        width: 900,
      );

      final valueTop = tester.getTopLeft(find.text('142'));
      final listTop = tester.getTopLeft(find.byKey(const Key('metric-card-source-option-trainer')));
      expect(listTop.dx, greaterThan(valueTop.dx));
      // Beside, not stacked further down the same column: the two starting
      // points sit within one row's height of each other.
      expect((listTop.dy - valueTop.dy).abs(), lessThan(30));
    });
  });
}

/// The grid always lays two tiles per row — this fills the second slot so
/// the tile under test renders at its real half-width rather than the full
/// width of the harness's `SizedBox`.
class _FillerCard extends StatelessWidget {
  const _FillerCard();

  @override
  Widget build(BuildContext context) => const MetricCard(
    icon: LucideIcons.gauge,
    iconColor: Color(0xFF0EA5E9),
    label: 'SPEED',
    value: null,
    unit: 'km/h',
  );
}
