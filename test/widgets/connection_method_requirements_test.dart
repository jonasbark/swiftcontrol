// Regression: `requirements:` is built inside the tiles' `build()`, so every
// rebuild hands ConnectionMethod a fresh list whose `status` is still false.
// ConnectionMethod probed one list, awaited, then re-read `widget.requirements`
// — picking up the unprobed list and opening the permission sheet for a
// permission that was actually granted. The sheet then sat there, because
// PermissionList only re-probes on app resume.
import 'dart:async';

import 'package:bike_control/bluetooth/devices/trainer_connection.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart' show OtherLocalizationsDelegate;
import 'package:bike_control/utils/actions/base_actions.dart';
import 'package:bike_control/utils/keymap/keymap.dart';
import 'package:bike_control/utils/requirements/platform.dart';
import 'package:bike_control/widgets/ui/connection_method.dart';
import 'package:bike_control/widgets/ui/permissions_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../widget_snapshot.dart';

/// Gate-controlled so the test can force a rebuild while the probe is in
/// flight — the exact window the bug lives in.
class _GatedRequirement extends PlatformRequirement {
  _GatedRequirement(this.gate) : super('Local Network', icon: Icons.wifi);

  final Future<void> gate;

  @override
  Future<bool> getStatus() async {
    await gate;
    status = true;
    return true;
  }

  @override
  Future<void> call(BuildContext context, VoidCallback onUpdate) async {}
}

class _FakeConnection extends TrainerConnection {
  _FakeConnection() : super(title: () => 'Direct connection', type: ConnectionMethodType.network, supportedActions: const []);

  @override
  Future<ActionResult> sendAction(KeyPair keyPair, {required bool isKeyDown, required bool isKeyUp}) async =>
      NotHandled('', button: null);

  @override
  Widget getTile({bool small = false}) => const SizedBox.shrink();
}

/// Mirrors the real tiles: the requirement list is rebuilt from a factory on
/// every build, so each rebuild yields brand-new objects.
class _Host extends StatefulWidget {
  const _Host({required this.gate, required this.rebuild});

  final Future<void> gate;
  final Listenable rebuild;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final connection = _FakeConnection();
  bool enabled = true;

  @override
  void initState() {
    super.initState();
    widget.rebuild.addListener(_onRebuild);
  }

  @override
  void dispose() {
    widget.rebuild.removeListener(_onRebuild);
    super.dispose();
  }

  void _onRebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ConnectionMethod(
      trainerConnection: connection,
      title: 'Direct connection',
      description: 'desc',
      isRecommended: false,
      isEnabled: enabled,
      small: false,
      onChange: (value) => setState(() => enabled = value),
      // Fresh objects on every build, exactly like localNetworkRequirements().
      requirements: [_GatedRequirement(widget.gate)],
    );
  }
}

Future<void> main() async {
  await ensureSnapshotHarness();

  testWidgets('a rebuild mid-probe does not open the permission sheet for a granted permission', (tester) async {
    final gate = Completer<void>();
    final rebuild = ChangeNotifier();
    addTearDown(rebuild.dispose);

    await tester.pumpWidget(
      ShadcnApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: [
          ...ShadcnLocalizations.localizationsDelegates,
          const OtherLocalizationsDelegate(),
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(child: _Host(gate: gate.future, rebuild: rebuild)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pump();

    // The tile rebuilds while the probe is still in flight — a ValueNotifier
    // on isConnected/isStarted firing, or onChange's own setState.
    rebuild.notifyListeners();
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byType(PermissionList),
      findsNothing,
      reason: 'the permission was granted; the sheet must not open',
    );
  });
}
