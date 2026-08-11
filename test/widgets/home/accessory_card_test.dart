import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/widgets/home/accessory_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Future<void> pumpAccessory(
  WidgetTester tester, {
  required bool connected,
  VoidCallback? onOpen,
}) async {
  await tester.pumpWidget(
    ShadcnApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      theme: ThemeData(colorScheme: ColorSchemes.lightSlate, radius: 0.5),
      home: Scaffold(
        child: SingleChildScrollView(
          child: AccessoryCard(
            title: 'HEADWIND F123',
            icon: LucideIcons.fan,
            connected: connected,
            onOpen: onOpen ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('names the accessory and says it is connected', (tester) async {
    await pumpAccessory(tester, connected: true);

    expect(find.text('HEADWIND F123'), findsOneWidget);
    expect(find.text(AppLocalizations.current.connected), findsOneWidget);
  });

  testWidgets('a disconnected accessory says so instead', (tester) async {
    await pumpAccessory(tester, connected: false);

    expect(find.text(AppLocalizations.current.notConnected), findsOneWidget);
  });

  // The card exists so a stray accessory — a neighbour's Headwind the scanner
  // picked up — can be opened and put on the ignore list. Without this tap
  // there is no route to its settings anywhere in the app.
  testWidgets('opens the accessory settings when tapped', (tester) async {
    var opened = 0;
    await pumpAccessory(tester, connected: true, onOpen: () => opened++);

    await tester.tap(find.text(AppLocalizations.current.chainEdit));
    await tester.pumpAndSettle();

    expect(opened, 1);
  });
}
