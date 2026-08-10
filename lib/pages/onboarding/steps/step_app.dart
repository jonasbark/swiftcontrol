import 'package:bike_control/pages/button_edit.dart' show SelectableCard;
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/keymap/apps/supported_app.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Step 1 body — grid of trainer apps grouped into "officially supported"
/// and "other", tap to select. Continue is driven by the page's footer.
Widget onboardingAppBody(BuildContext context,
    {required SupportedApp? selected, required ValueChanged<SupportedApp> onSelect}) {
  final official = SupportedApp.supportedApps.where((a) => a.officialIntegration).toList();
  final other = SupportedApp.supportedApps.where((a) => !a.officialIntegration).toList();

  Widget grid(List<SupportedApp> apps) => LayoutBuilder(builder: (context, constraints) {
        final cols = constraints.maxWidth >= 560 ? 5 : 3;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.1,
          children: [
            for (final app in apps)
              SelectableCard(
                isActive: selected?.name == app.name,
                alignment: Alignment.center,
                title: Center(
                  child: app.logoAsset != null
                      ? Image.asset(app.logoAsset!, height: 36, fit: BoxFit.contain)
                      : Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: Theme.of(context).colorScheme.muted,
                          ),
                          child: Text(app.name.substring(0, 1).toUpperCase()).semiBold.muted,
                        ),
                ),
                subtitle: Center(child: Text(app.name, textAlign: TextAlign.center).xSmall.semiBold),
                onPressed: () => onSelect(app),
              ),
          ],
        );
      });

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.i18n.onboardingAppTitle).h4,
      Gap(6),
      Text(context.i18n.onboardingAppSubtitle).small.muted,
      Gap(18),
      Text(context.i18n.officiallySupported).xSmall.semiBold.muted,
      Gap(8),
      grid(official),
      Gap(18),
      Text(context.i18n.otherTrainerApps).xSmall.semiBold.muted,
      Gap(8),
      grid(other),
      Gap(14),
      Text(context.i18n.onboardingAppNote).xSmall.muted,
    ],
  );
}
