import 'package:bike_control/pages/button_edit.dart' show SelectableCard;
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Widget onboardingWhereBody(BuildContext context,
    {required SupportedApp app, required Target? selected, required ValueChanged<Target> onSelect}) {
  String enables(Target t) => t == Target.thisDevice
      ? context.i18n.onboardingWhereEnablesLocal
      : context.i18n.onboardingWhereEnablesNetwork;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.i18n.onboardingWhereTitle(app.name)).h4,
      Gap(6),
      Text(context.i18n.onboardingWhereSubtitle).small.muted,
      Gap(18),
      for (final target in [Target.thisDevice, Target.otherDevice]) ...[
        SelectableCard(
          isActive: selected == target,
          title: Row(children: [
            Icon(target.icon, size: 22),
            Gap(12),
            Expanded(child: Text(target.getTitle(context)).semiBold),
          ]),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Gap(4),
              Text(target.getDescription(app)).xSmall.muted,
              Gap(8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: selected == target
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.09)
                      : Theme.of(context).colorScheme.muted,
                ),
                child: Text(enables(target)).xSmall,
              ),
            ],
          ),
          onPressed: () => onSelect(target),
        ),
        Gap(10),
      ],
      Gap(4),
      Text(context.i18n.onboardingWhereChangeLater).xSmall.muted,
    ],
  );
}
