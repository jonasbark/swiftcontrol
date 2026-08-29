import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/ui/warning.dart';
import 'package:prop/prop.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tells the rider why their right puck's lights keep going dark.
///
/// The puck itself stays on regardless — BikeControl sees to that with or
/// without a sibling. What a nearby left puck buys is the lights, and nothing
/// on the card would otherwise explain why they go out on a controller that is
/// plainly still working. Shown only in that state; once a left puck turns up
/// the sequence re-runs and this goes away on its own.
class ClickV2KeepAwakeWarning extends StatelessWidget {
  const ClickV2KeepAwakeWarning({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ClickKeepAwakeStatus>(
      valueListenable: ClickLogic.keepAwakeStatus,
      builder: (context, status, _) {
        if (status != ClickKeepAwakeStatus.waitingForLeftSide) {
          return const SizedBox.shrink();
        }
        return Warning(
          important: false,
          children: [
            Text(context.i18n.clickV2_keepAwakeNeedsLeftSide).xSmall,
          ],
        );
      },
    );
  }
}
