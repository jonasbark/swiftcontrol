import 'dart:async';

import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/bluetooth_device.dart';
import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/devices/steering_device.dart';
import 'package:bike_control/bluetooth/messages/notification.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/models/remembered_device.dart';
import 'package:bike_control/pages/controller_settings.dart';
import 'package:bike_control/pages/home/chain_builder.dart';
import 'package:bike_control/pages/home/chain_inputs.dart';
import 'package:bike_control/pages/home/chain_state.dart';
import 'package:bike_control/pages/home/home_extras.dart';
import 'package:bike_control/pages/home/home_sheets.dart';
import 'package:bike_control/pages/proxy_device_details.dart';
import 'package:bike_control/pages/trainer_connection_settings.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:bike_control/utils/keymap/apps/bike_control.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/utils/requirements/multi.dart';
import 'package:bike_control/widgets/controller/controller_canvas.dart';
import 'package:bike_control/widgets/controller/steering_gauge.dart';
import 'package:bike_control/widgets/home/ampel.dart';
import 'package:bike_control/widgets/home/chain_card.dart';
import 'package:bike_control/widgets/home/chain_labels.dart';
import 'package:bike_control/widgets/home/ready_banner.dart';
import 'package:bike_control/widgets/home/trial_card.dart';
import 'package:bike_control/widgets/ui/animated_button_widget.dart';
import 'package:bike_control/widgets/ui/toast.dart';
import 'package:dartx/dartx.dart';
import 'package:prop/prop.dart' show LogLevel;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The Main tab: the setup chain.
///
/// One card per link, in signal-path order — your controllers, then the gears
/// BikeControl computes from them, then the app that receives them. Each card
/// states its own status and its own remaining steps, so a rider who opens the
/// app can answer "am I ready?" without tapping anything, and a rider whose
/// ride just broke can see *which* link failed instead of a screen of green
/// widgets that are all technically telling the truth.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.isMobile,
    required this.onUpdate,
    this.showHelpRow = true,
    this.onHelp,
  });

  final bool isMobile;

  /// Lets the host clear its error banner when the rider acts on a card.
  final VoidCallback onUpdate;

  /// Hidden on wide desktop, where the activity rail already carries a Help
  /// button and a second one would be redundant.
  final bool showHelpRow;
  final VoidCallback? onHelp;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final StreamSubscription<BaseDevice> _connectionListener;
  late final StreamSubscription<BaseNotification> _actionListener;
  Timer? _metricsTicker;

  /// Assumed available until proven otherwise, so the step doesn't flash as
  /// pending on every cold start before the platform has answered.
  bool _bluetoothReady = true;

  final Map<String, ControllerButton> _pressedButton = {};
  final Map<String, int> _pressGeneration = {};

  @override
  void initState() {
    super.initState();

    _connectionListener = core.connection.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
    _actionListener = core.connection.actionStream.listen((notification) {
      if (notification is ButtonNotification && notification.buttonsClicked.isNotEmpty) {
        final id = notification.device.uniqueId;
        _pressGeneration[id] = (_pressGeneration[id] ?? 0) + 1;
        if (mounted) setState(() => _pressedButton[id] = notification.buttonsClicked.first);
      }
    });

    // Live trainer telemetry lives behind several notifiers that swap when the
    // trainer changes mode. A slow tick is cheaper to reason about than
    // re-subscribing on every transition, and it only runs while a trainer is
    // actually connected.
    // Not started under the screenshot harness: a periodic timer never lets a
    // widget test's frame loop go quiet, and the captured metrics are fixtures
    // there anyway.
    if (!screenshotMode) {
      _metricsTicker = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted && core.connection.proxyDevices.any((p) => p.isConnected)) setState(() {});
      });
    }

    _refreshBluetoothState();
    IAPManager.instance.isPurchased.addListener(_onPurchaseChanged);
  }

  @override
  void dispose() {
    _connectionListener.cancel();
    _actionListener.cancel();
    _metricsTicker?.cancel();
    IAPManager.instance.isPurchased.removeListener(_onPurchaseChanged);
    super.dispose();
  }

  void _onPurchaseChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshBluetoothState() async {
    try {
      final ready = await BluetoothTurnedOn().getStatus();
      if (mounted && ready != _bluetoothReady) setState(() => _bluetoothReady = ready);
    } catch (e, s) {
      recordError(e, s, context: 'HomePage bluetooth availability');
    }
  }

  // ── Reading the world ─────────────────────────────────────────────────

  /// Every controller the app knows about: the live ones first, then the
  /// remembered stand-ins for devices that aren't here right now.
  List<BaseDevice> get _knownControllers => [
    ...core.connection.controllerDevices,
    ...core.connection.offlineControllers,
  ];

  DevicePresence _presenceOf(BaseDevice device, {required bool isStandIn}) {
    if (device.isConnected) return DevicePresence.connected;
    if (device.isResetting) return DevicePresence.resetting;
    // The distinction that keeps a fresh launch calm: only a device that was
    // working in *this* session counts as broken.
    if (core.connection.wasConnectedThisSession(device.uniqueId)) return DevicePresence.lost;
    // A stand-in comes from the remembered list, so we know the rider owns it
    // and it is merely out of range. Anything else is something the scanner
    // just found and we have never connected to — "not set up", not "broken".
    return isStandIn ? DevicePresence.remembered : DevicePresence.discovered;
  }

  bool _hasMappedButtons(BaseDevice device) {
    final keymap = core.actionHandler.supportedApp?.keymap;
    if (keymap == null) return false;
    return device.availableButtons.any(keymap.hasAnyMappedAction);
  }

  ChainInputs _readInputs() {
    final controllers = _knownControllers;
    final standInIds = core.connection.offlineControllers.map((d) => d.uniqueId).toSet();
    final trainerApp = core.settings.getTrainerApp();
    final proxy = core.connection.proxyDevices.sortedBy((p) => p.isConnected ? 0 : 1).firstOrNull;
    final remembered = core.connection.rememberedTrainer;

    TrainerInput? trainer;
    if (proxy != null) {
      final config = core.shiftingConfigs.configsFor(proxy.trainerKey);
      trainer = TrainerInput(
        deviceId: proxy.uniqueId,
        name: proxy.toString(),
        presence: _presenceOf(proxy, isStandIn: false),
        gearsConfigured: config.isNotEmpty,
        gearsSummary: _gearsSummary(proxy),
        metrics: _trainerMetrics(proxy),
      );
    } else if (remembered != null) {
      trainer = TrainerInput(
        deviceId: remembered.deviceId,
        name: remembered.name ?? context.i18n.chainTrainerTitle,
        presence: DevicePresence.remembered,
        gearsConfigured: core.shiftingConfigs.configsFor(remembered.name ?? remembered.deviceId).isNotEmpty,
      );
    }

    return ChainInputs(
      bluetoothReady: _bluetoothReady,
      controllers: [
        for (final device in controllers)
          ControllerInput(
            deviceId: device.uniqueId,
            name: device.toString(),
            presence: _presenceOf(device, isStandIn: standInIds.contains(device.uniqueId)),
            hasMappedButtons: _hasMappedButtons(device),
            requiresBluetooth: device is BluetoothDevice,
          ),
      ],
      trainer: trainer,
      app: AppInput(
        name: trainerApp?.name,
        selfHosted: trainerApp is BikeControl,
        hasEnabledConnection: core.logic.enabledTrainerConnections.isNotEmpty,
        isConnected: core.logic.connectedTrainerConnections.isNotEmpty,
        wasConnectedThisSession: _appConnectedThisSession,
        connectionSummary: core.logic.connectedTrainerConnections.firstOrNull?.title,
      ),
    );
  }

  bool _appConnectedThisSession = false;

  String? _gearsSummary(ProxyDevice proxy) {
    final config = core.shiftingConfigs.configsFor(proxy.trainerKey).firstOrNull;
    if (config == null) return null;
    return context.i18n.onboardingVirtualTrainerGears('${config.maxGear}');
  }

  /// A compact, plain-text version of the trainer's live telemetry for the
  /// status line. The full metric row still lives on the trainer's own page.
  String? _trainerMetrics(ProxyDevice proxy) {
    if (!proxy.isConnected) return null;
    final bike = proxy.fitnessBike;
    if (bike == null) return null;
    final parts = <String>[
      if ((bike.powerW.value ?? 0) > 0) '${bike.powerW.value} W',
      if ((bike.cadenceRpm.value ?? 0) > 0) '${bike.cadenceRpm.value} rpm',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final inputs = _readInputs();
    // Latch once connected: the app card can then say "lost connection" rather
    // than falling back to "never set up" the moment the app quits.
    if (inputs.app.isConnected) _appConnectedThisSession = true;

    final links = buildChain(inputs);
    final banner = deriveBanner(links);
    final devicesById = {for (final d in _knownControllers) d.uniqueId: d};
    final trial = _trialState();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReadyBanner(
            banner: banner,
            appName: inputs.app.name,
            brokenLinkName: _linkName(links, banner.targetLinkId),
            onAction: banner.hasAction ? () => _openInstructions(links.firstWhere((l) => l.id == banner.targetLinkId)) : null,
          ),
          if (trial != null) ...[
            TrialCard(
              state: trial,
              onUpgrade: () => IAPManager.instance.purchaseFullVersion(context),
              onRestore: () => IAPManager.instance.restorePurchases(),
            ),
            const Gap(10),
          ],
          for (final link in links) ...[
            _card(link, devicesById[link.deviceId], inputs),
            const Gap(10),
          ],
          HomeExtras(isMobile: widget.isMobile, onUpdate: _update),
          if (widget.showHelpRow) ...[
            const Gap(12),
            Button.outline(
              onPressed: widget.onHelp ?? () => openControllerHelpSheet(context),
              child: Row(
                children: [
                  Icon(LucideIcons.lifeBuoy, size: 17, color: Theme.of(context).colorScheme.primary),
                  const Gap(9),
                  Expanded(
                    child: Text(
                      context.i18n.chainSomethingNotWorking,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 15, color: Theme.of(context).colorScheme.mutedForeground),
                ],
              ),
            ),
          ],
          if (widget.isMobile) Gap(MediaQuery.viewPaddingOf(context).bottom + 32),
        ],
      ),
    );
  }

  void _update() {
    widget.onUpdate();
    if (mounted) setState(() {});
  }

  String? _linkName(List<ChainLink> links, String? id) {
    if (id == null) return null;
    final link = links.firstOrNullWhere((l) => l.id == id);
    if (link == null) return null;
    return link.title.isNotEmpty ? link.title : chainLinkName(context, link.key);
  }

  TrialCardState? _trialState() {
    final iap = IAPManager.instance;
    // The reward for paying is one less thing on screen.
    if (iap.isPurchased.value || iap.isProEnabledForCurrentDevice) return null;

    final trainerConnected = core.connection.proxyDevices.any((p) => p.isConnected);
    final bridge = core.bridgeUsageTracker;
    return TrialCardState(
      daysRemaining: iap.trialDaysRemaining,
      daysTotal: _trialDaysTotal,
      expired: iap.isTrialExpired,
      commandsRemaining: iap.commandsRemainingToday,
      commandsTotal: IAPManager.dailyCommandLimit,
      bridgeMinutesRemaining: trainerConnected ? bridge.remainingToday.inMinutes : null,
      bridgeMinutesTotal: trainerConnected ? bridge.dailyLimit.inMinutes : null,
    );
  }

  /// The trial's full length, inferred from the largest remaining count we have
  /// seen, so the meter never shows a value above its own ceiling.
  int get _trialDaysTotal {
    final remaining = IAPManager.instance.trialDaysRemaining;
    return remaining > _knownTrialDays ? remaining : _knownTrialDays;
  }

  static const int _knownTrialDays = 5;

  // ── Cards ─────────────────────────────────────────────────────────────

  Widget _card(ChainLink link, BaseDevice? device, ChainInputs inputs) {
    final card = switch (link.key) {
      ChainLinkKey.controller => _controllerCard(link, device, inputs),
      ChainLinkKey.trainer => _trainerCard(link, inputs),
      ChainLinkKey.app => _appCard(link, inputs),
    };

    if (!link.dismissible) return card;

    // Only a device that isn't here can be swiped away, so this gesture can
    // never drop a working controller off the screen.
    return Dismissible(
      key: ValueKey('dismiss-${link.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: AmpelStyle.of(context, LinkStatus.problem).wash,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(LucideIcons.trash2, size: 20, color: AmpelStyle.of(context, LinkStatus.problem).color),
      ),
      onDismissed: (_) => _forget(link),
      child: card,
    );
  }

  Widget _controllerCard(ChainLink link, BaseDevice? device, ChainInputs inputs) {
    final placeholder = device == null;
    final status = link.status;

    return ChainCard(
      link: link,
      appName: inputs.app.name,
      tile: Icon(
        placeholder ? LucideIcons.gamepad : device.icon,
        size: 22,
        color: status == LinkStatus.off
            ? Theme.of(context).colorScheme.mutedForeground
            : Theme.of(context).colorScheme.foreground,
      ),
      title: placeholder ? context.i18n.chainControllerTitle : link.title,
      statusLabel: _controllerStatusLabel(status),
      editLabel: placeholder ? context.i18n.chainSetUp : context.i18n.chainEdit,
      onEdit: placeholder
          ? () => openControllerSetupSheet(context).then((_) => _update())
          : () async {
              await context.push(ControllerSettingsPage(device: device));
              _update();
            },
      onInstructions: () => _openInstructions(link),
      instructionsLabel: placeholder ? context.i18n.chainSetUp : null,
      body: placeholder ? null : _controllerBody(device, connected: device.isConnected),
    );
  }

  String _controllerStatusLabel(LinkStatus status) => switch (status) {
    LinkStatus.ready => context.i18n.connected,
    LinkStatus.problem => context.i18n.chainStatusLostConnection,
    LinkStatus.attention => context.i18n.chainStatusOutOfRange,
    LinkStatus.off => context.i18n.chainStatusNotSetUp,
  };

  /// The controller's real contour with its real buttons — so the card doubles
  /// as the button map. Rendered for disconnected devices too, faded: mapping a
  /// button is a keymap edit, not a radio operation, so there is no reason to
  /// make a rider wait until they are back on the bike to do it.
  Widget _controllerBody(BaseDevice device, {required bool connected}) {
    final keymap = core.actionHandler.supportedApp?.keymap;
    final size = 56 / Theme.of(context).scaling;

    Widget buttonFor(ControllerButton button) {
      final pressed = _pressedButton[device.uniqueId];
      return AnimatedButtonWidget(
        key: ValueKey(button.name),
        button: button,
        pressGeneration: pressed?.name == button.name ? (_pressGeneration[device.uniqueId] ?? 0) : 0,
        keymap: keymap,
        device: device,
        size: size,
        onUpdate: _update,
      );
    }

    final Widget content;
    if (device is SteeringDevice) {
      final steering = device as SteeringDevice;
      content = SteeringGauge(
        angle: steering.steeringAngle,
        calibrated: steering.steeringCalibrated,
        threshold: steering.steeringThreshold,
        device: device,
        leftButton: steering.steerLeftButton,
        rightButton: steering.steerRightButton,
        keymap: keymap,
        onUpdate: _update,
      );
    } else {
      final layout = device.controllerLayout;
      content = layout != null
          ? ControllerCanvas(
              layout: layout,
              availableButtons: device.availableButtons,
              buttonBuilder: buttonFor,
              buttonSize: size,
            )
          : Wrap(spacing: 9, runSpacing: 9, children: device.availableButtons.map(buttonFor).toList());
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedOpacity(
            opacity: connected ? 1 : 0.55,
            duration: const Duration(milliseconds: 250),
            child: content,
          ),
          if (!connected) ...[
            const Gap(8),
            Text(context.i18n.chainOfflineEditNotice).xSmall.muted,
          ],
        ],
      ),
    );
  }

  Widget _trainerCard(ChainLink link, ChainInputs inputs) {
    final proxy = core.connection.proxyDevices.sortedBy((p) => p.isConnected ? 0 : 1).firstOrNull;
    final appReady = inputs.app.isConnected;
    final appName = inputs.app.name;

    final String statusLabel;
    if (link.status == LinkStatus.ready) {
      statusLabel = context.i18n.connected;
    } else if (link.status == LinkStatus.problem) {
      statusLabel = context.i18n.chainStatusLostConnection;
    } else if (link.status == LinkStatus.off && appReady && appName != null) {
      // Only vouch for the app handling shifting when the app is actually
      // working — otherwise this card would excuse a broken link.
      statusLabel = context.i18n.chainStatusHandledByApp(appName);
    } else {
      statusLabel = context.i18n.notConnected;
    }

    return ChainCard(
      link: link,
      appName: appName,
      tile: Icon(
        LucideIcons.bike,
        size: 22,
        color: link.status == LinkStatus.ready
            ? Theme.of(context).colorScheme.foreground
            : Theme.of(context).colorScheme.mutedForeground,
      ),
      title: link.title.isEmpty ? context.i18n.chainTrainerTitle : link.title,
      statusLabel: statusLabel,
      editLabel: proxy == null ? context.i18n.connect : context.i18n.chainEdit,
      onEdit: () async {
        if (proxy != null) {
          await context.push(ProxyDeviceDetailsPage(device: proxy));
        } else {
          await openControllerSetupSheet(context);
        }
        _update();
      },
      onInstructions: () => _openInstructions(link),
    );
  }

  Widget _appCard(ChainLink link, ChainInputs inputs) {
    final app = core.settings.getTrainerApp();
    final logo = app?.logoAsset;

    final String statusLabel;
    if (link.status == LinkStatus.ready) {
      statusLabel = context.i18n.chainStatusReceivingCommands;
    } else if (link.status == LinkStatus.problem) {
      statusLabel = context.i18n.notConnected;
    } else if (app != null) {
      statusLabel = context.i18n.chainStatusWaitingForApp(app.name);
    } else {
      statusLabel = context.i18n.chainStatusNotSetUp;
    }

    return ChainCard(
      link: link,
      appName: inputs.app.name,
      tile: logo != null
          ? ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.asset(logo, width: 30, height: 30))
          : Icon(LucideIcons.monitor, size: 22, color: Theme.of(context).colorScheme.mutedForeground),
      title: link.title.isEmpty ? context.i18n.chainAppTitle : link.title,
      statusLabel: statusLabel,
      onEdit: () async {
        await context.push(const TrainerConnectionSettingsPage());
        _update();
      },
      onInstructions: () => _openInstructions(link),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────

  /// Instruction sheets are routed on the card and its state, never on the
  /// wording of the active step — so a never-paired controller gets the pairing
  /// flow while a paired-then-dropped one gets the reconnect checklist.
  Future<void> _openInstructions(ChainLink link) async {
    switch (link.key) {
      case ChainLinkKey.controller:
        if (link.status == LinkStatus.off) {
          await openControllerSetupSheet(context);
        } else {
          await openControllerHelpSheet(context);
        }
      case ChainLinkKey.trainer:
        await openTrainerHelpSheet(context);
      case ChainLinkKey.app:
        await openAppGuideSheet(context);
    }
    _update();
  }

  Future<void> _forget(ChainLink link) async {
    final deviceId = link.deviceId;
    if (deviceId == null) return;

    // Capture the entry and its copy before anything awaits, so Undo puts back
    // exactly what was removed rather than a reconstruction of it.
    final entry = core.rememberedDevices.load().firstOrNullWhere((d) => d.deviceId == deviceId);
    final toastTitle = context.i18n.chainForgotten(
      link.title.isNotEmpty ? link.title : chainLinkName(context, link.key),
    );
    final undoLabel = context.i18n.chainUndo;

    final index = await core.connection.forgetRemembered(deviceId);
    if (mounted) setState(() {});

    if (entry == null) return;
    buildToast(
      level: LogLevel.LOGLEVEL_INFO,
      title: toastTitle,
      closeTitle: undoLabel,
      onClose: () => _restore(entry, index),
    );
  }

  Future<void> _restore(RememberedDevice device, int? index) async {
    await core.connection.restoreRemembered(device, atIndex: index);
    if (mounted) setState(() {});
  }
}
