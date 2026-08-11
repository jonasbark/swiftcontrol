import 'package:bike_control/pages/home/chain_state.dart';
import 'package:flutter_test/flutter_test.dart';

ChainLink link({
  required String id,
  ChainLinkKey key = ChainLinkKey.controller,
  LinkStatus status = LinkStatus.ready,
  bool optional = false,
  List<bool> steps = const [true],
}) {
  return ChainLink(
    key: key,
    id: id,
    status: status,
    title: id,
    optional: optional,
    steps: [
      for (final (i, done) in steps.indexed)
        SetupStep(id: SetupStepId.values[i % SetupStepId.values.length], done: done),
    ],
  );
}

void main() {
  group('ChainLink step counting', () {
    test('counts done and remaining steps', () {
      final l = link(id: 'a', steps: [true, false, false]);
      expect(l.doneSteps, 1);
      expect(l.remainingSteps, 2);
    });

    test('active step is the first unfinished one', () {
      final l = link(id: 'a', steps: [true, false, false]);
      expect(l.activeStepIndex, 1);
      expect(l.activeStep, isNotNull);
      expect(l.activeStep!.done, isFalse);
    });

    test('a complete checklist has no active step', () {
      final l = link(id: 'a', steps: [true, true]);
      expect(l.activeStepIndex, isNull);
      expect(l.activeStep, isNull);
      expect(l.remainingSteps, 0);
    });

    test('an empty checklist has no active step and does not crash', () {
      final l = link(id: 'a', steps: []);
      expect(l.activeStepIndex, isNull);
      expect(l.doneSteps, 0);
      expect(l.remainingSteps, 0);
      expect(l.startsExpanded, isFalse);
    });

    test('a done step later in the list does not become active', () {
      final l = link(id: 'a', steps: [false, true, false]);
      expect(l.activeStepIndex, 0);
    });
  });

  group('ChainLink.isBlocking', () {
    test('ready never blocks', () {
      expect(link(id: 'a', status: LinkStatus.ready).isBlocking, isFalse);
    });

    test('attention, problem and off all block a required link', () {
      for (final status in [LinkStatus.attention, LinkStatus.problem, LinkStatus.off]) {
        expect(link(id: 'a', status: status).isBlocking, isTrue, reason: status.name);
      }
    });

    test('an optional link at rest is not a blocker', () {
      expect(link(id: 't', status: LinkStatus.off, optional: true).isBlocking, isFalse);
    });

    test('an optional link that broke still blocks', () {
      expect(link(id: 't', status: LinkStatus.problem, optional: true).isBlocking, isTrue);
      expect(link(id: 't', status: LinkStatus.attention, optional: true).isBlocking, isTrue);
    });
  });

  group('startsExpanded', () {
    test('ready cards collapse', () {
      expect(link(id: 'a', status: LinkStatus.ready, steps: [true, true]).startsExpanded, isFalse);
    });

    test('unresolved cards open themselves', () {
      for (final status in [LinkStatus.attention, LinkStatus.problem, LinkStatus.off]) {
        expect(link(id: 'a', status: status, steps: [false]).startsExpanded, isTrue, reason: status.name);
      }
    });
  });

  group('deriveBanner', () {
    test('everything ready gives a calm banner with no action', () {
      final banner = deriveBanner([
        link(id: 'c', status: LinkStatus.ready),
        link(id: 'trainer', status: LinkStatus.off, optional: true),
        link(id: 'app', status: LinkStatus.ready),
      ]);
      expect(banner.kind, ChainBannerKind.ready);
      expect(banner.status, LinkStatus.ready);
      expect(banner.stepsLeft, 0);
      expect(banner.hasAction, isFalse);
      expect(banner.targetLinkId, isNull);
    });

    test('an optional link at rest does not spoil "ready to ride"', () {
      final banner = deriveBanner([
        link(id: 'c', status: LinkStatus.ready),
        link(id: 'trainer', status: LinkStatus.off, optional: true, steps: [false, false]),
      ]);
      expect(banner.kind, ChainBannerKind.ready);
      expect(banner.stepsLeft, 0);
    });

    test('counts outstanding steps across every blocking link', () {
      final banner = deriveBanner([
        link(id: 'c', status: LinkStatus.attention, steps: [true, false, false]),
        link(id: 'app', status: LinkStatus.attention, steps: [true, false]),
      ]);
      expect(banner.kind, ChainBannerKind.pending);
      expect(banner.stepsLeft, 3);
    });

    test('ignores steps left on non-blocking links', () {
      // A ready card with a stale unfinished step must not inflate the count.
      final banner = deriveBanner([
        link(id: 'c', status: LinkStatus.ready, steps: [true, false]),
        link(id: 'app', status: LinkStatus.attention, steps: [false]),
      ]);
      expect(banner.stepsLeft, 1);
    });

    test('pending targets the first blocking link in render order', () {
      final banner = deriveBanner([
        link(id: 'c', status: LinkStatus.ready),
        link(id: 'trainer', status: LinkStatus.attention, steps: [false]),
        link(id: 'app', status: LinkStatus.attention, steps: [false]),
      ]);
      expect(banner.targetLinkId, 'trainer');
    });

    test('a broken link outranks an unfinished one wherever it sits', () {
      final banner = deriveBanner([
        link(id: 'app', status: LinkStatus.attention, steps: [false]),
        link(id: 'c', status: LinkStatus.problem, steps: [true, false]),
      ]);
      expect(banner.kind, ChainBannerKind.broken);
      expect(banner.status, LinkStatus.problem);
      expect(banner.targetLinkId, 'c');
      // The count still covers everything outstanding, not just the break.
      expect(banner.stepsLeft, 2);
    });

    test('the first broken link wins when several broke', () {
      final banner = deriveBanner([
        link(id: 'c1', status: LinkStatus.problem, steps: [false]),
        link(id: 'c2', status: LinkStatus.problem, steps: [false]),
      ]);
      expect(banner.targetLinkId, 'c1');
    });

    test('outstanding keys are distinct and in render order', () {
      final banner = deriveBanner([
        link(id: 'c1', key: ChainLinkKey.controller, status: LinkStatus.attention, steps: [false]),
        link(id: 'c2', key: ChainLinkKey.controller, status: LinkStatus.attention, steps: [false]),
        link(id: 'app', key: ChainLinkKey.app, status: LinkStatus.attention, steps: [false]),
      ]);
      expect(banner.outstandingKeys, [ChainLinkKey.controller, ChainLinkKey.app]);
    });

    test('an empty chain is treated as ready rather than crashing', () {
      final banner = deriveBanner([]);
      expect(banner.kind, ChainBannerKind.ready);
      expect(banner.hasAction, isFalse);
    });

    test('the banner target is always a link that is actually in the chain', () {
      final links = [
        link(id: 'c', status: LinkStatus.ready),
        link(id: 'app', status: LinkStatus.attention, steps: [false]),
      ];
      final banner = deriveBanner(links);
      expect(links.map((l) => l.id), contains(banner.targetLinkId));
    });
  });
}
