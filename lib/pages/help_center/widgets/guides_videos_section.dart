// "Tutorials & Videos" section body — the how-to-connect article link, the
// bikecontrol.app/tutorials link, and the instruction-videos drawer. The
// article link and the videos drawer are lifted unchanged from the old
// help-button dropdown (Task 8); the tutorials link replaced the blog list
// that used to sit below this card in design round 1 (blog coverage now
// lives only on the overview page).
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/help_article.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'instruction_videos_section.dart';

class GuidesVideosSection extends StatelessWidget {
  const GuidesVideosSection({super.key});

  @override
  Widget build(BuildContext context) {
    final controllers = core.connection.controllerDevices;
    final article = helpArticleFor(
      context,
      controller: controllers.isEmpty ? null : controllers.first,
      app: core.settings.getTrainerApp(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (article != null)
          Button.ghost(
            onPressed: () => launchUrlString(article.url),
            child: Basic(
              leading: const Icon(Icons.menu_book_outlined, size: 18),
              title: Text(article.label),
              trailing: const Icon(Icons.chevron_right, size: 16).iconMutedForeground,
            ),
          ),
        Button.ghost(
          key: const ValueKey('help-center-tutorials'),
          onPressed: () => launchUrlString('https://bikecontrol.app/tutorials'),
          child: Basic(
            leading: const Icon(Icons.play_circle_outline, size: 18),
            title: const Text('Tutorials'),
            trailing: const Icon(Icons.chevron_right, size: 16).iconMutedForeground,
          ),
        ),
        Button.ghost(
          onPressed: () {
            openDrawer(
              context: context,
              position: OverlayPosition.bottom,
              builder: (c) => const InstructionVideosDrawer(),
            );
          },
          child: Basic(
            leading: const Icon(Icons.ondemand_video, size: 18),
            title: const Text('Instruction Videos'),
            trailing: const Icon(Icons.chevron_right, size: 16).iconMutedForeground,
          ),
        ),
      ],
    );
  }
}
