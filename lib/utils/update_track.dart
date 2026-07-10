import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Maps the beta-tester flag (the `beta_access` entitlement) to the Shorebird
/// update track the app checks for patches.
UpdateTrack updateTrackFor({required bool isBetaTester}) =>
    isBetaTester ? UpdateTrack.beta : UpdateTrack.stable;
