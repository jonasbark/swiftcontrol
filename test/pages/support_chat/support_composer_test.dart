import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/support_chat/widgets/support_composer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Regression test for the diagnostic-info sheet (the ⓘ button next to Send).
/// A real diagnostic payload includes the full log buffer, so the sheet grew
/// past the screen and left no barrier to tap — with no close button, drag
/// handle or back-route the user had to kill the app to escape.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(String payload) {
    return ShadcnApp(
      localizationsDelegates: [
        ...ShadcnLocalizations.localizationsDelegates,
        AppLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(
        child: SupportComposer(
          sending: false,
          onSend: (_, _) async {},
          diagnosticPreview: payload,
        ),
      ),
    );
  }

  testWidgets('diagnostic sheet with a huge payload can be closed via its X button', (tester) async {
    // Realistic payload: JSON-encoded telemetry incl. hundreds of log lines.
    final payload = List.generate(400, (i) => '"log$i": "2026-07-09 10:00:$i - entry"').join('\n');
    await tester.pumpWidget(app(payload));
    await tester.pump();

    await tester.tap(find.byIcon(LucideIcons.info));
    await tester.pumpAndSettle();

    // Sheet is open and shows the payload.
    expect(find.textContaining('"log0"'), findsOneWidget);

    // It must offer an explicit close affordance that dismisses it.
    final close = find.byIcon(LucideIcons.x);
    expect(close, findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();

    expect(find.textContaining('"log0"'), findsNothing);
  });
}
