import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/ui/warning.dart';
import 'package:prop/prop.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tells the rider why their right puck is still going to power itself off.
///
/// Keeping it awake needs both pucks on the air once. When only the right one
/// is connected there is nothing the app can do about it, and nothing on the
/// card would otherwise say so — the puck simply switches off a minute later
/// and looks broken. Shown only in that state; the moment the left puck
/// connects the sequence runs and this goes away on its own.
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
