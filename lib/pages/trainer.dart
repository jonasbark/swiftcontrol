import 'package:bike_control/pages/configuration.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/widgets/apps/connection_tiles.dart';
import 'package:bike_control/widgets/trainer_features.dart';
import 'package:bike_control/widgets/ui/colored_title.dart';
import 'package:flutter/foundation.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class TrainerPage extends StatefulWidget {
  final bool isMobile;
  final VoidCallback onUpdate;
  final VoidCallback goToNextPage;
  const TrainerPage({super.key, required this.onUpdate, required this.goToNextPage, required this.isMobile});

  @override
  State<TrainerPage> createState() => _TrainerPageState();
}

class _TrainerPageState extends State<TrainerPage> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    if (!kIsWeb) {
      core.whooshLink.isStarted.addListener(() {
        if (mounted) setState(() {});
      });

      core.zwiftEmulator.isConnected.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = buildConnectionMethodTiles(
      small: false,
      onUpdate: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    final recommendedTiles = tiles.recommended;
    final otherTiles = tiles.other;

    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.only(bottom: 16, left: 16, right: 16, top: 16),
        child: Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: 800),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConfigurationPage(
                  onUpdate: () {
                    setState(() {});
                    widget.onUpdate();
                  },
                ),
                if (core.settings.getTrainerApp() != null && core.settings.getLastTarget() != null) ...[
                  if (recommendedTiles.isNotEmpty) ...[
                    Gap(32),
                    ColoredTitle(text: context.i18n.recommendedConnectionMethods),
                    Gap(12),
                  ],

                  for (final tile in recommendedTiles) ...[
                    IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: tile,
                      ),
                    ),
                  ],
                  Gap(12),
                  if (otherTiles.isNotEmpty) ...[
                    SizedBox(height: 8),
                    Accordion(
                      items: [
                        AccordionItem(
                          trigger: AccordionTrigger(
                            child: ColoredTitle(text: context.i18n.otherConnectionMethods),
                          ),
                          content: Column(
                            children: [
                              for (final tile in otherTiles)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: IntrinsicHeight(child: tile),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Gap(8),
                    Divider(),
                  ],
                  const Gap(24),
                  TrainerFeatures(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
