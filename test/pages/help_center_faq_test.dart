// Task 11: the "Pricing & account" FAQ section body. Pins: the accordion
// renders all 8 Q/A pairs (one row per FAQ key), all collapsed by default,
// and tapping a question's trigger reveals that question's answer. Finds
// widgets by `ValueKey`, not literal copy, so translated builds and future
// copy edits don't break the test.
//
// Content-round addition: two more FAQ items ("still shows Trial/Basic" and
// "bought on one store, use on another") plus a rework of `faqRestore`'s
// copy in place (same key — see pricing_faq_section.dart's header comment).
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/pages/help_center/widgets/pricing_faq_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    ShadcnApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const faqKeys = [
    'faqOneTime',
    'faqPro',
    'faqStillTrial',
    'faqTrial',
    'faqGrandfather',
    'faqRefund',
    'faqCrossStore',
    'faqRestore',
  ];

  group('PricingFaqSection', () {
    testWidgets('renders a trigger for each of the 8 FAQ items, all collapsed', (tester) async {
      await _pump(tester, const PricingFaqSection());
      await tester.pump();

      for (final key in faqKeys) {
        expect(find.byKey(ValueKey('help-faq-question-$key')), findsOneWidget, reason: '$key question missing');
        expect(find.byKey(ValueKey('help-faq-answer-$key')), findsNothing, reason: '$key answer should be collapsed');
      }
    });

    testWidgets('expanding one item reveals its answer without affecting the others', (tester) async {
      await _pump(tester, const PricingFaqSection());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('help-faq-question-faqTrial')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('help-faq-answer-faqTrial')), findsOneWidget);
      for (final key in faqKeys.where((k) => k != 'faqTrial')) {
        expect(find.byKey(ValueKey('help-faq-answer-$key')), findsNothing);
      }
    });
  });
}
