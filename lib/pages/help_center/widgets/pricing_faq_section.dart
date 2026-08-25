// "Pricing & account" FAQ section body (Task 11). Six Q/A rows covering the
// one-time purchase, the Pro subscription, the daily virtual-shifting trial,
// the pre-subscription "grandfather" purchases, refunds, and restoring
// purchases after a reinstall.
//
// Copy was fact-checked against `IAPManager` (isProEnabledForCurrentDevice /
// hasPurchasedBefore50RVC / ensureProForFeature), `paywall.dart`'s feature
// matrix, and the existing `virtualShiftingProNote` / `bridgeTrialTimeOverBody`
// strings before being written — see task-11-report.md for the corrections
// that came out of that check (most notably: the free virtual-shifting trial
// is a 20-minute *daily* allowance that resets every day, not a per-ride
// limit, and the pre-subscription grandfather explicitly does not extend to
// virtual shifting).
//
// shadcn_flutter's `Accordion`/`AccordionItem` keep their `content` mounted
// in the tree at all times (collapsed to zero height via `SizeTransition`
// rather than removed), which would make collapsed-vs-expanded assertions by
// key impossible. This rolls a minimal single-expansion accordion instead —
// `Button.ghost` triggers per house convention, with each answer only
// entering the widget tree while its row is expanded.
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class _FaqItem {
  final String key;
  final String question;
  final String answer;

  const _FaqItem({required this.key, required this.question, required this.answer});
}

class PricingFaqSection extends StatefulWidget {
  const PricingFaqSection({super.key});

  @override
  State<PricingFaqSection> createState() => _PricingFaqSectionState();
}

class _PricingFaqSectionState extends State<PricingFaqSection> {
  String? _expandedKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.i18n;
    final items = <_FaqItem>[
      _FaqItem(key: 'faqOneTime', question: l10n.faqOneTimeQ, answer: l10n.faqOneTimeA),
      _FaqItem(key: 'faqPro', question: l10n.faqProQ, answer: l10n.faqProA),
      _FaqItem(key: 'faqTrial', question: l10n.faqTrialQ, answer: l10n.faqTrialA),
      _FaqItem(key: 'faqGrandfather', question: l10n.faqGrandfatherQ, answer: l10n.faqGrandfatherA),
      _FaqItem(key: 'faqRefund', question: l10n.faqRefundQ, answer: l10n.faqRefundA),
      _FaqItem(key: 'faqRestore', question: l10n.faqRestoreQ, answer: l10n.faqRestoreA),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(),
          _FaqRow(
            item: items[i],
            expanded: _expandedKey == items[i].key,
            onTap: () => setState(() {
              _expandedKey = _expandedKey == items[i].key ? null : items[i].key;
            }),
          ),
        ],
      ],
    );
  }
}

class _FaqRow extends StatelessWidget {
  final _FaqItem item;
  final bool expanded;
  final VoidCallback onTap;

  const _FaqRow({required this.item, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Button.ghost(
          key: ValueKey('help-faq-question-${item.key}'),
          // Bug 6: the default ghost-button padding read as cramped for an
          // accordion trigger — bump it using the same
          // `ButtonStyle.ghost().withPadding(...)` idiom vs_stage.dart uses,
          // with the 12 this file's own answer padding already established.
          style: ButtonStyle.ghost().withPadding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
          onPressed: onTap,
          child: Basic(
            title: Text(item.question),
            trailing: Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 18,
            ).iconMutedForeground,
          ),
        ),
        if (expanded)
          Padding(
            key: ValueKey('help-faq-answer-${item.key}'),
            // 16 matches the "comfortable" bottom breathing room
            // HelpCenterSectionCard/InstructionVideosDrawer already use
            // elsewhere in the Help Center; the 4 top gap separates the
            // answer from the question above it instead of hugging it.
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Text(item.answer).muted.small,
          ),
      ],
    );
  }
}
