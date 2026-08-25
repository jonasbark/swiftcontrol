// "Your setup" personalized section (Task 9) — rows built from the rider's
// actual configured controllers instead of static links: one help-article
// row per distinct controller (deduped by article URL), a network
// troubleshooting row while a network trainer connection is active, a Zwift
// Click V2 setup-options row while a Click V2 side is known (live or
// remembered), and a muted nudge toward the setup wizard when nothing is
// configured yet.
import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/trainer_connection.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/pages/click_v2_onboarding.dart';
import 'package:bike_control/pages/network_troubleshooting_page.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/help_article.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

class YourSetupSection extends StatelessWidget {
  /// Test seam: replaces the device pool this section reads from — in
  /// production that's `core.connection.controllerDevices` for the
  /// help-article rows and `core.connection.devices` +
  /// `core.connection.offlineControllers` (live + remembered) for the Click
  /// V2 check. `core` is a convenient global in production but awkward to
  /// fake piecemeal in a widget test, so a single override list stands in
  /// for both when provided — see help_center_your_setup_test.dart.
  final List<BaseDevice>? devicesOverride;

  /// Test seam: replaces `core.logic.trainerConnections`.
  final List<TrainerConnection>? connectionsOverride;

  const YourSetupSection({super.key, this.devicesOverride, this.connectionsOverride});

  @override
  Widget build(BuildContext context) {
    final l10n = context.i18n;

    final knownDevices =
        devicesOverride ?? <BaseDevice>{...core.connection.devices, ...core.connection.offlineControllers}.toList();
    final articleDevices = devicesOverride ?? core.connection.controllerDevices;
    final connections = connectionsOverride ?? core.logic.trainerConnections;

    final app = core.settings.getTrainerApp();
    final articles = <String, HelpArticle>{};
    for (final controller in articleDevices) {
      final article = helpArticleFor(context, controller: controller, app: app);
      if (article != null) articles[article.url] = article;
    }

    final hasNetworkConnection = connections.any(
      (t) => t.type == ConnectionMethodType.network && (t.isStarted.value || t.isConnected.value),
    );
    final hasClickV2 = knownDevices.any((d) => d is ZwiftClickV2 || d is ZwiftClickV2RightSide);

    // Matches the mockup's row padding (`padding:11px 14px`) now that the
    // card itself carries no padding — rows run edge-to-edge and supply
    // their own inset.
    final rowStyle = ButtonStyle.ghost().withPadding(padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14));

    final rows = <Widget>[
      for (final article in articles.values)
        Button.ghost(
          style: rowStyle,
          onPressed: () => launchUrlString(article.url),
          child: Basic(
            leading: const Icon(Icons.menu_book_outlined, size: 18),
            title: Text(article.label),
            trailing: const Icon(Icons.chevron_right, size: 16).iconMutedForeground,
          ),
        ),
      if (hasNetworkConnection)
        Button.ghost(
          key: const ValueKey('help-network-troubleshoot'),
          style: rowStyle,
          onPressed: () => context.push(const NetworkTroubleshootingPage()),
          child: Basic(
            leading: const Icon(Icons.wifi_tethering, size: 18),
            title: Text(l10n.helpCenterNetworkEntry),
            trailing: const Icon(Icons.chevron_right, size: 16).iconMutedForeground,
          ),
        ),
      if (hasClickV2)
        Button.ghost(
          key: const ValueKey('help-clickv2-onboarding'),
          style: rowStyle,
          onPressed: () => context.push(const ClickV2OnboardingPage()),
          child: Basic(
            leading: const Icon(Icons.tune, size: 18),
            title: Text(l10n.helpCenterClickV2Entry),
            trailing: const Icon(Icons.chevron_right, size: 16).iconMutedForeground,
          ),
        ),
    ];

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        child: Text(l10n.helpCenterNoSetup).muted.small,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(),
          rows[i],
        ],
      ],
    );
  }
}
