import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/proxy_device_details/metric_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The tile itself — presentational only, and deliberately dumb: it renders
/// whatever [MetricSourceRow] it is given. `live_metrics_section_test.dart`
/// covers deciding WHEN a row appears and what state it resolves to; this
/// file covers HOW [MetricCard] renders a given one.
Future<void> main() async {
  await AppLocalizations.load(const Locale('en'));

  Future<void> pump(WidgetTester tester, MetricCard card) async {
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(child: Row(children: [card])),
      ),
    );
  }

  Color? dotColor(WidgetTester tester) {
    final container = tester.widget<Container>(find.byKey(const Key('metric-card-source-dot')));
    return (container.decoration as BoxDecoration?)?.color;
  }

  const baseCard = MetricCard(
    icon: LucideIcons.heart,
    iconColor: Color(0xFFEF4444),
    label: 'HEART',
    value: '142',
    unit: 'bpm',
  );

  group('THE INVARIANT: source omitted', () {
    testWidgets('renders label, value and unit with no row at all', (tester) async {
      await pump(tester, baseCard);

      expect(find.text('HEART'), findsOneWidget);
      expect(find.text('142'), findsOneWidget);
      expect(find.text('bpm'), findsOneWidget);
      expect(find.byKey(const Key('metric-card-source-row')), findsNothing);
    });

    testWidgets('a null value renders the unchanged "--" placeholder, still no row', (tester) async {
      await pump(
        tester,
        const MetricCard(
          icon: LucideIcons.heart,
          iconColor: Color(0xFFEF4444),
          label: 'HEART',
          value: null,
          unit: 'bpm',
        ),
      );

      expect(find.text('--'), findsOneWidget);
      expect(find.byKey(const Key('metric-card-source-row')), findsNothing);
    });
  });

  group('source row dot state', () {
    testWidgets('trainer: muted dot, "Trainer" label', (tester) async {
      final cs = await _pumpAndScheme(tester, pump, baseCard, MetricSourceState.trainer, 'Trainer');

      expect(find.text('Trainer'), findsOneWidget);
      expect(dotColor(tester), cs.mutedForeground);
    });

    testWidgets('connected: green dot, the sensor\'s own display name as label', (tester) async {
      await _pumpAndScheme(tester, pump, baseCard, MetricSourceState.connected, 'HR6 0050789');

      expect(find.text('HR6 0050789'), findsOneWidget);
      expect(dotColor(tester), const Color(0xFF22C55E));
    });

    testWidgets('connecting: amber dot', (tester) async {
      await _pumpAndScheme(tester, pump, baseCard, MetricSourceState.connecting, 'Connecting…');

      expect(dotColor(tester), const Color(0xFFF59E0B));
    });

    testWidgets('waiting for first reading: amber dot too — same colour as connecting', (tester) async {
      await _pumpAndScheme(tester, pump, baseCard, MetricSourceState.waitingForFirstReading, 'Waiting…');

      expect(dotColor(tester), const Color(0xFFF59E0B));
    });

    testWidgets('lost: red dot', (tester) async {
      await _pumpAndScheme(tester, pump, baseCard, MetricSourceState.lost, 'Signal lost');

      expect(dotColor(tester), const Color(0xFFEF4444));
    });
  });

  testWidgets('the row text stays muted foreground regardless of state — only the dot carries state', (tester) async {
    final cs = await _pumpAndScheme(tester, pump, baseCard, MetricSourceState.lost, 'Signal lost');

    final text = tester.widget<Text>(find.text('Signal lost'));
    expect(text.style?.color, cs.mutedForeground);
    expect(text.style?.fontSize, 12);
    expect(text.style?.fontWeight, FontWeight.w500);
  });

  testWidgets('tapping the row invokes onTap', (tester) async {
    var tapped = false;
    await pump(
      tester,
      MetricCard(
        icon: baseCard.icon,
        iconColor: baseCard.iconColor,
        label: baseCard.label,
        value: baseCard.value,
        unit: baseCard.unit,
        source: MetricSourceRow(state: MetricSourceState.trainer, label: 'Trainer', onTap: () => tapped = true),
      ),
    );

    await tester.tap(find.byKey(const Key('metric-card-source-row')));
    await tester.pump();

    expect(tapped, isTrue);
  });
}

Future<ColorScheme> _pumpAndScheme(
  WidgetTester tester,
  Future<void> Function(WidgetTester, MetricCard) pump,
  MetricCard base,
  MetricSourceState state,
  String label,
) async {
  await pump(
    tester,
    MetricCard(
      icon: base.icon,
      iconColor: base.iconColor,
      label: base.label,
      value: base.value,
      unit: base.unit,
      source: MetricSourceRow(state: state, label: label, onTap: () {}),
    ),
  );
  return Theme.of(tester.element(find.byType(MetricCard))).colorScheme;
}
