import 'package:bike_control/bluetooth/devices/gyroscope/gyroscope_steering.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/widgets/controller/steering_wheel_gauge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'widget_snapshot.dart';

/// Renders the steering-wheel gauge at a fixed 8° tilt (past the default 5°
/// threshold, so the LEFT zone glows). Run:
/// `flutter test test/steering_wheel_gauge_snapshot_test.dart`
Future<void> main() async {
  await ensureSnapshotHarness();

  final device = GyroscopeSteering();
  final angle = ValueNotifier<double>(8.0);
  final calibrated = ValueNotifier<bool>(true);

  Widget gauge() => SizedBox(
        height: 220,
        child: SteeringWheelGauge(
          angle: angle,
          calibrated: calibrated,
          threshold: 5,
          device: device,
          leftButton: GyroscopeSteeringButtons.leftSteer,
          rightButton: GyroscopeSteeringButtons.rightSteer,
          // keymap/onUpdate omitted ⇒ halves are inert (snapshot only).
        ),
      );

  testWidgets('SteeringWheelGauge (active left) → PNG light/dark', (tester) async {
    await captureWidget(
      tester,
      name: 'steering_wheel_gauge_light',
      width: 360,
      locales: const ['en', 'de'],
      builder: (context) => gauge(),
    );
    await captureWidget(
      tester,
      name: 'steering_wheel_gauge_dark',
      width: 360,
      brightness: Brightness.dark,
      builder: (context) => gauge(),
    );
  });

  testWidgets('SteeringWheelGauge (calibrating) → PNG', (tester) async {
    calibrated.value = false;
    await captureWidget(
      tester,
      name: 'steering_wheel_gauge_calibrating',
      width: 360,
      // settle:false because the SmallProgressIndicator spinner never settles.
      settle: false,
      builder: (context) => gauge(),
    );
  });
}
