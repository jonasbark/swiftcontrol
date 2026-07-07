import 'package:bike_control/utils/update_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

void main() {
  group('updateTrackFor', () {
    test('beta testers check the beta track', () {
      expect(updateTrackFor(isBetaTester: true), UpdateTrack.beta);
    });

    test('everyone else checks the stable track', () {
      expect(updateTrackFor(isBetaTester: false), UpdateTrack.stable);
    });
  });
}
