import '../emulation_profile.dart';
import 'elite_profiles.dart';
import 'zwift_profiles.dart';

/// Every device the debug "Emulate device" menu can add. Extended per family
/// in later tasks; keep controllers first, then steering, then accessories.
List<EmulationProfile> get allEmulationProfiles => [
      zwiftClickProfile,
      zwiftClickV2LeftProfile,
      zwiftClickV2RightProfile,
      zwiftPlayLeftProfile,
      zwiftPlayRightProfile,
      zwiftPlayFw2Profile,
      zwiftRideProfile,
      eliteSquareProfile,
      eliteSterzoProfile,
      eliteRizerProfile,
    ];
