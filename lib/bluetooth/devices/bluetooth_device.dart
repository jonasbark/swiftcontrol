import 'dart:async';

import 'package:bike_control/bluetooth/ble.dart';
import 'package:bike_control/bluetooth/devices/base_device.dart';
import 'package:bike_control/bluetooth/devices/openbikecontrol/openbikecontrol_device.dart';
import 'package:bike_control/bluetooth/devices/proxy/proxy_device.dart';
import 'package:bike_control/bluetooth/devices/shimano/shimano_di2.dart';
import 'package:bike_control/bluetooth/devices/sram/sram_axs.dart';
import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_bike_pro.dart';
import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_bike_shift.dart';
import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_climb.dart';
import 'package:bike_control/bluetooth/devices/wahoo/wahoo_kickr_headwind.dart';
import 'package:bike_control/bluetooth/devices/zwift/constants.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_click.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_left_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_clickv2_right_side.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_device.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_play.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_play_fw2.dart';
import 'package:bike_control/bluetooth/devices/zwift/zwift_ride.dart';
import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/services/sensors/ble_sensor_source.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/i18n_extension.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:bike_control/utils/keymap/buttons.dart';
import 'package:bike_control/widgets/ui/toast.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
// `SramAdvertisement` clashes with nothing here, but the prop package also
// exports a `SramAxs` constants class that collides with this file's `SramAxs`
// app device import above — pull in only what's needed to avoid the clash.
import 'package:prop/prop.dart' show LogLevel, SramAdvertisement;
import 'package:prop/utils/wahoo_climb.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'cycplus/cycplus_bc2.dart';
import 'elite/elite_rizer.dart';
import 'elite/elite_square.dart';
import 'elite/elite_sterzo.dart';
import 'ltwoo/ltwoo_erx.dart';
import 'sensors/ble_cadence_device.dart';
import 'sensors/ble_heart_rate_device.dart';
import 'sensors/ble_power_device.dart';
import 'thinkrider/thinkrider_vs200.dart';
import 'wheeltop/wheeltop_eds.dart';

abstract class BluetoothDevice extends BaseDevice {
  final BleDevice scanResult;

  BluetoothDevice(
    this.scanResult, {
    required List<ControllerButton> availableButtons,
    bool allowMultiple = false,
    bool isBeta = false,
    bool supportsLongPress = true,
    IconData icon = LucideIcons.gamepad,
    String? buttonPrefix,
  }) : super(
         scanResult.name,
         icon: icon,
         uniqueId: scanResult.deviceId,
         availableButtons: allowMultiple
             ? availableButtons.toList().map((b) => b.copyWith(sourceDeviceId: scanResult.deviceId)).toList()
             : availableButtons.toList(),
         isBeta: isBeta,
         supportsLongPress: supportsLongPress,
         buttonPrefix: buttonPrefix,
       ) {
    rssi = scanResult.rssi;
  }

  int? batteryLevel;
  String? firmwareVersion;
  String? hardwareRevision;
  String? manufacturerName;
  String? deviceName;
  int? rssi;

  static List<String> servicesToScan = [
    ZwiftConstants.ZWIFT_CUSTOM_SERVICE_UUID,
    ZwiftConstants.ZWIFT_CUSTOM_SERVICE_SHORT_UUID,
    ZwiftConstants.ZWIFT_RIDE_CUSTOM_SERVICE_UUID,
    SquareConstants.SERVICE_UUID,
    WahooKickrBikeShiftConstants.SERVICE_UUID,
    WahooKickrHeadwindConstants.SERVICE_UUID,
    wahooClimbServiceUuid,
    SterzoConstants.SERVICE_UUID,
    CycplusBc2Constants.SERVICE_UUID,
    ShimanoDi2Constants.SERVICE_UUID,
    ShimanoDi2Constants.SERVICE_UUID_ALTERNATIVE,
    OpenBikeControlConstants.SERVICE_UUID,
    ThinkRiderVs200Constants.SERVICE_UUID,
    // Nordic UART Service — needed so L-TWOO derailleurs show up in filtered
    // scans; device matching itself stays name-gated (NUS is far too generic).
    LtwooErxConstants.SERVICE_UUID,
    // Heart Rate Service — so straps and armbands appear in filtered scans and
    // can be selected as an external source.
    BleSensorSource.heartRateServiceUuid,
    // Cycling Speed and Cadence Service — so cadence-only sensors appear in
    // filtered scans and can be selected as an external source.
    BleSensorSource.cscServiceUuid,
    // Cycling Power Service — so power meters appear in filtered scans; see
    // the power-meter opt-in gate in fromScanResult for why some of them are
    // hidden by default even once discovered.
    BleSensorSource.cyclingPowerServiceUuid,
  ];

  /// Power-meter name prefixes hidden from scanning by default — the product
  /// decision about which brands are known to accept only one simultaneous
  /// BLE connection, so surfacing them unprompted would risk silently
  /// costing the rider their existing pairing (see
  /// `Settings.getPowerMeterOptIn`'s doc comment). Used only by the
  /// name-based exclusion at the top of [fromScanResult].
  ///
  /// Deliberately NOT the same list as [_powerMeterNames]: which brands
  /// BikeControl hides by default is a narrower product decision than which
  /// brands it can RECOGNISE as a power meter at all once a rider opts in —
  /// see that list's doc comment for the defect conflating the two caused.
  static final List<String> _hiddenPowerMeterNames = ['ASSIOMA', 'QUARQ', 'POWERCRANK'];

  /// Every power-meter name prefix BikeControl recognises for classification
  /// — a superset of [_hiddenPowerMeterNames]. Used by the narrow, opted-in
  /// `BlePowerDevice` rules in [fromScanResult] (both platform branches).
  ///
  /// Before this was split from the hide-by-default list, a meter could only
  /// ever be CLASSIFIED as a [BlePowerDevice] if it was ALSO HIDDEN by
  /// default — so an opted-in rider with, say, a Stages or 4iiii power meter
  /// (real brands, never hidden, and so never recognised either) could not
  /// select it as an external source no matter what they did: the narrow
  /// rule's name check never matched, and the meter kept resolving to
  /// whatever the bare-CPS fallback produced instead.
  static final List<String> _powerMeterNames = [
    ..._hiddenPowerMeterNames,
    'STAGES',
    '4IIII',
    'SRM',
    'RALLY', // Garmin Rally
    'ROTOR',
    'POWER2MAX',
    'POWRLINK', // Wahoo POWRLINK
  ];

  /// Whether [name] matches one of the power-meter families BikeControl
  /// recognises for classification ([_powerMeterNames]) — the narrow,
  /// opted-in `BlePowerDevice` rules in [fromScanResult] use this.
  static bool _isKnownPowerMeterName(String name) =>
      _powerMeterNames.any((knownName) => name.toUpperCase().startsWith(knownName));

  /// Whether [name] matches one of the power-meter families BikeControl
  /// hides by default ([_hiddenPowerMeterNames]) — the name-based exclusion
  /// at the top of [fromScanResult] uses this. Deliberately narrower than
  /// [_isKnownPowerMeterName]: see [_powerMeterNames]'s doc comment for why
  /// a meter can be recognised without being hidden.
  static bool _isHiddenPowerMeterName(String name) =>
      _hiddenPowerMeterNames.any((hiddenName) => name.toUpperCase().startsWith(hiddenName));

  /// Test seam: overrides the effective [kIsWeb] check so `fromScanResult`'s
  /// web-specific classification branch can be exercised from a normal
  /// (Dart VM) test run, where the real compile-time [kIsWeb] is always
  /// false. Mirrors `ObpMdnsEmulator.debugIsWindows`. Reset to null once the
  /// test that set it is done, or it silently pins every later test in the
  /// same run to that platform.
  @visibleForTesting
  static bool Function()? debugIsWeb;

  static bool get _effectiveIsWeb => (debugIsWeb ?? (() => kIsWeb))();

  List<BleService>? services;

  /// §2.1: BikeControl should only connect to the SRAM AXS rear derailleur —
  /// bare shifters/blips/pods also advertise service 0xFE51 but aren't
  /// connectable targets. Uses the advertised device-type record to tell them
  /// apart; when it's absent or unparsable, falls back to the previous
  /// behavior (connect).
  static bool _sramIsConnectable(BleDevice scanResult) {
    Uint8List? record;
    for (final e in scanResult.serviceData.entries) {
      if (e.key.toLowerCase().contains('fe51')) {
        record = e.value;
        break;
      }
    }
    if (record == null) return true; // no service data → can't tell; keep current behavior
    final info = SramAdvertisement.parse(record);
    if (info == null) return true;
    return info.isRearDerailleur; // connect only to the rear derailleur
  }

  /// Whether a scan result points at a Zwift Ride on genuinely old,
  /// third-party-incompatible firmware — the only case the "update the
  /// firmware" toast should fire for.
  ///
  /// A modern Ride advertises two manufacturer-data types: `RIDE_LEFT_SIDE`
  /// (which builds a [ZwiftRide]) and `RIDE_RIGHT_SIDE` (deliberately mapped to
  /// null — we only connect to the left half). The right-side advert therefore
  /// builds no device yet still exposes the Zwift custom service, so
  /// [hasZwiftCustomService] is what separates it from an old Ride that exposes
  /// no recognizable Zwift service at all (ticket ed826861, issue #2).
  @visibleForTesting
  static bool isLikelyOldRideFirmware({
    required String? name,
    required bool deviceRecognized,
    required bool hasZwiftCustomService,
  }) => name == 'Zwift Ride' && !deviceRecognized && !hasZwiftCustomService;

  static BluetoothDevice? fromScanResult(BleDevice scanResult) {
    // Skip devices with hidden names — unless the rider has explicitly
    // opted in to power meters that are known to accept only one BLE
    // connection at a time (see Settings.getPowerMeterOptIn's doc comment).
    if (scanResult.name != null && !core.settings.getPowerMeterOptIn() && _isHiddenPowerMeterName(scanResult.name!)) {
      return null;
    }

    // Use the name first as the "System Devices" and Web (android sometimes Windows) don't have manufacturer data
    BluetoothDevice? device;
    if (_effectiveIsWeb) {
      device = switch (scanResult.name) {
        'Zwift Ride' => ZwiftRide(scanResult),
        'Zwift Play' => ZwiftPlay(scanResult, deviceType: ZwiftDeviceType.playLeft),
        'Zwift Click' => ZwiftClickV2(scanResult),
        'SQUARE' => EliteSquare(scanResult),
        'OpenBike' => OpenBikeControlDevice(scanResult),
        null => null,
        _ when scanResult.name!.toUpperCase().startsWith('KICKR CLIMB') && IAPManager.instance.isBetaTester =>
          WahooKickrClimb(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('HEADWIND') => WahooKickrHeadwind(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('STERZO') => EliteSterzo(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('RIZER') && IAPManager.instance.isBetaTester => EliteRizer(
          scanResult,
        ),
        _ when scanResult.name!.toUpperCase().startsWith('KICKR BIKE SHIFT') => WahooKickrBikeShift(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('KICKR BIKE PRO') => WahooKickrBikePro(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('KICKR BIKE') => WahooKickrBikeShift(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('CYCPLUS') && scanResult.name!.toUpperCase().contains('BC2') =>
          CycplusBc2(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('THINK VS') => ThinkRiderVs200(scanResult),
        _ when LtwooErxConstants.matchesName(scanResult.name) => LtwooErx(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('RDR') => ShimanoDi2(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('SRAM') && _sramIsConnectable(scanResult) => SramAxs(
          scanResult,
        ),
        // Heart rate straps are matched by advertised service, never by name
        // (TICKR, H10, HRM-Dual, Rhythm24, ... vary too widely) — and this
        // rule MUST stay last: trainers routinely relay a paired strap and
        // advertise 0x180D themselves, so matching it earlier would steal a
        // trainer away from its own device class.
        _ when scanResult.services.contains(BleSensorSource.heartRateServiceUuid) => BleHeartRateDevice(scanResult),
        // Cadence sensors and power meters, matched by advertised service
        // for the same reason heart rate is above — and these rules MUST
        // also stay last: trainers advertise CSC (0x1816) and Cycling Power
        // (0x1818) far more readily than they advertise heart rate, so
        // matching either earlier would misclassify a trainer as a plain
        // sensor and break bridging entirely. This branch has no
        // ProxyDevice case to protect against (web never builds one), so
        // today this narrow, name-gated rule produces exactly the same
        // BlePowerDevice the broad rule below it does — both require opt-in,
        // and once that is true the name check no longer changes the
        // outcome. Kept anyway so the two switch branches have the same
        // shape and do not silently diverge if a ProxyDevice-equivalent is
        // ever added here, which would need the ordering the non-web branch
        // already relies on. See that branch's version of this rule for why
        // the narrow form is the one that matters there today.
        _
            when core.settings.getPowerMeterOptIn() &&
                scanResult.name != null &&
                _isKnownPowerMeterName(scanResult.name!) &&
                scanResult.services.contains(BleSensorSource.cyclingPowerServiceUuid) =>
          BlePowerDevice(scanResult),
        // Power is checked before cadence so a combo device advertising both
        // services (common — many power meters also expose CSC) resolves to
        // the richer BlePowerDevice rather than being downgraded to
        // cadence-only.
        //
        // Gated on opt-in alone — deliberately broader than the narrow rule
        // above on name, since BikeControl cannot enumerate every power
        // meter brand that exists, and a rider who already opted in
        // (Settings.getPowerMeterOptIn) has said they understand a power
        // meter may accept only one simultaneous BLE connection. This rule
        // used to have NO opt-in check at all: a comment here called it
        // "redundant" with the narrow rule above, but it was not — it was
        // THE gate, and it was ungated, so any device advertising bare
        // Cycling Power became a BlePowerDevice unconditionally, able to
        // take a rider's power meter away from a bike computer it was
        // already paired to with no consent at all.
        _
            when core.settings.getPowerMeterOptIn() &&
                scanResult.services.contains(BleSensorSource.cyclingPowerServiceUuid) =>
          BlePowerDevice(scanResult),
        _ when scanResult.services.contains(BleSensorSource.cscServiceUuid) => BleCadenceDevice(scanResult),
        _ => null,
      };
    } else {
      device = switch (scanResult.name) {
        null => null,
        //'Zwift Ride' => ZwiftRide(scanResult), special case for Zwift Ride: we must only connect to the left controller
        // https://www.makinolo.com/blog/2024/07/26/zwift-ride-protocol/
        //'Zwift Play' => ZwiftPlay(scanResult),
        //'Zwift Click' => ZwiftClick(scanResult), special case for Zwift Click v2: we must only connect to the left controller
        _ when scanResult.name!.toUpperCase().startsWith('KICKR CLIMB') && IAPManager.instance.isBetaTester =>
          WahooKickrClimb(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('HEADWIND') => WahooKickrHeadwind(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('SQUARE') => EliteSquare(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('STERZO') => EliteSterzo(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('RIZER') && IAPManager.instance.isBetaTester => EliteRizer(
          scanResult,
        ),
        _ when scanResult.name!.toUpperCase().contains('KICKR BIKE SHIFT') => WahooKickrBikeShift(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('KICKR BIKE PRO') => WahooKickrBikePro(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('KICKR BIKE') => WahooKickrBikeShift(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('CYCPLUS') && scanResult.name!.toUpperCase().contains('BC2') =>
          CycplusBc2(scanResult),
        _ when scanResult.name!.toUpperCase().startsWith('THINK VS') => ThinkRiderVs200(scanResult),
        _ when LtwooErxConstants.matchesName(scanResult.name) => LtwooErx(scanResult),
        //_ when scanResult.services.contains(CycplusBc2Constants.SERVICE_UUID.toLowerCase()) => CycplusBc2(scanResult),
        _ when scanResult.services.contains(ShimanoDi2Constants.SERVICE_UUID.toLowerCase()) => ShimanoDi2(scanResult),
        _ when scanResult.services.contains(ShimanoDi2Constants.SERVICE_UUID_ALTERNATIVE.toLowerCase()) => ShimanoDi2(
          scanResult,
        ),
        // Before the ProxyDevice branch below, which claims Cycling Power
        // (0x1818) unconditionally via containsAny — including for a
        // legitimately-named, opted-in power meter, which is wrong. This
        // rule is deliberately narrow to avoid the opposite mistake: it only
        // fires for a device the rider has explicitly opted in to AND whose
        // name we already recognise as a power meter (_isKnownPowerMeterName,
        // built from _powerMeterNames — a SUPERSET of the
        // _hiddenPowerMeterNames list the exclusion above uses, so a brand
        // can be recognised here without also being hidden by default).
        // A power-only TRAINER that also advertises bare CPS (no FTMS) is not
        // in that name list, so it is untouched by this rule and keeps
        // resolving to ProxyDevice.
        _
            when core.settings.getPowerMeterOptIn() &&
                scanResult.name != null &&
                _isKnownPowerMeterName(scanResult.name!) &&
                scanResult.services.contains(BleSensorSource.cyclingPowerServiceUuid) =>
          BlePowerDevice(scanResult),
        _
            when scanResult.services.containsAny(ProxyDevice.proxyServiceUUIDs) ||
                scanResult.serviceData.keys.containsAny(ProxyDevice.proxyServiceUUIDs) =>
          ProxyDevice(scanResult),
        _
            when scanResult.services.contains(SramAxsConstants.SERVICE_UUID.toLowerCase()) &&
                _sramIsConnectable(scanResult) =>
          SramAxs(scanResult),
        _ when scanResult.services.contains(OpenBikeControlConstants.SERVICE_UUID.toLowerCase()) =>
          OpenBikeControlDevice(scanResult),
        _ when scanResult.services.contains(WahooKickrHeadwindConstants.SERVICE_UUID.toLowerCase()) =>
          WahooKickrHeadwind(scanResult),
        _ when scanResult.services.contains(wahooClimbServiceUuid.toLowerCase()) => WahooKickrClimb(scanResult),
        // Heart rate straps are matched by advertised service, never by name
        // (TICKR, H10, HRM-Dual, Rhythm24, ... vary too widely) — and this
        // rule MUST stay last: trainers routinely relay a paired strap and
        // advertise 0x180D themselves, so matching it earlier (including
        // ahead of the ProxyDevice.proxyServiceUUIDs branch above) would
        // steal a trainer away from its own device class.
        _ when scanResult.services.contains(BleSensorSource.heartRateServiceUuid) => BleHeartRateDevice(scanResult),
        // Cadence sensors, matched by advertised service for the same reason
        // heart rate is above — and this rule MUST also stay last, including
        // after the ProxyDevice.proxyServiceUUIDs branch: trainers advertise
        // CSC (0x1816) far more readily than they advertise heart rate, so
        // matching it earlier would misclassify a trainer as a plain cadence
        // sensor and break bridging entirely. CSC has no overlap with
        // ProxyDevice.proxyServiceUUIDs, so, unlike the power rule above,
        // there is nothing narrower needed here.
        _ when scanResult.services.contains(BleSensorSource.cscServiceUuid) => BleCadenceDevice(scanResult),
        // Kept as a fallback for symmetry with the web branch below, but
        // unreachable here in practice: ProxyDevice.proxyServiceUUIDs already
        // contains this exact Cycling Power UUID with no name gate, so
        // anything that would satisfy this condition was already claimed by
        // the ProxyDevice branch above. The narrow, opted-in, name-gated rule
        // before ProxyDevice is what actually classifies a rider's power
        // meter on this branch — see its comment for why a broader
        // (name-unaware) rule can't safely sit ahead of ProxyDevice.
        _ when scanResult.services.contains(BleSensorSource.cyclingPowerServiceUuid) => BlePowerDevice(scanResult),
        // otherwise the service UUIDs will be used
        _ => null,
      };
    }

    final hasZwiftCustomService = scanResult.services.containsAny([
      ZwiftConstants.ZWIFT_CUSTOM_SERVICE_UUID.toLowerCase(),
      ZwiftConstants.ZWIFT_CUSTOM_SERVICE_SHORT_UUID.toLowerCase(),
      ZwiftConstants.ZWIFT_RIDE_CUSTOM_SERVICE_UUID.toLowerCase(),
    ]);

    if (device != null) {
      return device;
    } else if (hasZwiftCustomService) {
      // otherwise use the manufacturer data to identify the device
      final manufacturerData = scanResult.manufacturerDataList;
      final data = manufacturerData
          .firstOrNullWhere((e) => e.companyId == ZwiftConstants.ZWIFT_MANUFACTURER_ID)
          ?.payload;

      if (data == null || data.isEmpty) {
      } else {
        final type = ZwiftDeviceType.fromManufacturerData(data.first);
        // The split left/right controllers (with the new unlock handling) are
        // available to everyone now; a single toggle picks them over the
        // legacy unified [ZwiftClickV2]. Defaults on.
        final useNewUnlock = core.settings.getUseNewUnlockMethod();
        device = switch (type) {
          ZwiftDeviceType.click => ZwiftClick(scanResult),
          ZwiftDeviceType.playRight => ZwiftPlay(scanResult, deviceType: type!),
          ZwiftDeviceType.playLeft => ZwiftPlay(scanResult, deviceType: type!),
          ZwiftDeviceType.rideLeft => ZwiftRide(scanResult),
          ZwiftDeviceType.playFw2 => ZwiftPlayFw2(scanResult),
          //DeviceType.rideRight => ZwiftRide(scanResult), // see comment above
          ZwiftDeviceType.clickV2Left => useNewUnlock ? ZwiftClickV2LeftSide(scanResult) : ZwiftClickV2(scanResult),
          ZwiftDeviceType.clickV2Right => useNewUnlock ? ZwiftClickV2RightSide(scanResult) : null,
          _ => null,
        };
      }
    }

    // WHEELTOP EDS shifters advertise no usable name and no service UUIDs —
    // they are recognized by their manufacturer-data prefix alone.
    device ??= WheeltopEds.tryFrom(scanResult);

    if (isLikelyOldRideFirmware(
          name: scanResult.name,
          deviceRecognized: device != null,
          hasZwiftCustomService: hasZwiftCustomService,
        ) &&
        core.connection.controllerDevices.none((d) => d is ZwiftRide)) {
      // Fallback for Zwift Ride if nothing else matched => old firmware.
      // Naming the Companion app isn't enough — riders don't know firmware
      // updates live there, so the toast's action opens it directly.
      buildToast(
        level: LogLevel.LOGLEVEL_WARNING,
        title: AppLocalizations.current.firmwareUpdateRequired(scanResult.name!),
        closeTitle: AppLocalizations.current.zwiftCompanionApp,
        onClose: () => launchUrlString(ZwiftConstants.ZWIFT_COMPANION_URL, mode: LaunchMode.externalApplication),
        duration: Duration(seconds: 6),
      );
    }
    return device;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BluetoothDevice && runtimeType == other.runtimeType && scanResult.deviceId == other.scanResult.deviceId;

  @override
  int get hashCode => scanResult.deviceId.hashCode;

  BleDevice get device => scanResult;

  /// Consecutive failed auto-connect attempts before [Connection] stops
  /// retrying this device and surfaces [connectionGuidance]. 0 = retry forever.
  int get maxAutoConnectAttempts => 0;

  /// Actionable hint shown when auto-connect gives up (see
  /// [maxAutoConnectAttempts]); null when there is no device-specific guidance.
  String? get connectionGuidance => null;

  /// When true, [Connection] leaves this device in the reconnect loop even if
  /// it keeps dropping within seconds of connecting — i.e. it opts out of the
  /// quick-drop backoff. Default false. WheeltopEds returns true while its
  /// keepalive experiment runs, so each reconnect can try the next candidate.
  bool get keepsReconnectingWhileDropping => false;

  @override
  Future<void> connect() async {
    try {
      await connectUpstream();
    } catch (e) {
      isConnected = false;
      rethrow;
    }

    services = await discoverUpstreamServices();

    final deviceInformationService = services!.firstOrNullWhere(
      (service) => service.uuid == BleUuid.DEVICE_INFORMATION_SERVICE_UUID.toLowerCase(),
    );
    Future<String?> readStringChar(BleService? service, String charUuid) async {
      final characteristic = service?.characteristics.firstOrNullWhere(
        (c) => c.uuid == charUuid.toLowerCase(),
      );
      if (characteristic == null) return null;
      try {
        final data = await readUpstream(service!.uuid, characteristic.uuid);
        final decoded = String.fromCharCodes(data).trim();
        return decoded.isEmpty ? null : decoded;
      } catch (_) {
        return null;
      }
    }

    firmwareVersion = await readStringChar(
      deviceInformationService,
      BleUuid.DEVICE_INFORMATION_CHARACTERISTIC_FIRMWARE_REVISION,
    );
    hardwareRevision = await readStringChar(
      deviceInformationService,
      BleUuid.DEVICE_INFORMATION_CHARACTERISTIC_HARDWARE_REVISION,
    );
    manufacturerName = await readStringChar(
      deviceInformationService,
      BleUuid.DEVICE_INFORMATION_CHARACTERISTIC_MANUFACTURER_NAME,
    );

    final genericAccessService = services!.firstOrNullWhere(
      (service) => service.uuid == BleUuid.GENERIC_ACCESS_SERVICE_UUID.toLowerCase(),
    );
    deviceName =
        await readStringChar(
          genericAccessService,
          BleUuid.GENERIC_ACCESS_CHARACTERISTIC_DEVICE_NAME,
        ) ??
        device.name;

    if (firmwareVersion != null || hardwareRevision != null || manufacturerName != null || deviceName != null) {
      core.connection.signalChange(this);
    }

    final batteryService = services!.firstOrNullWhere(
      (service) => service.uuid == BleUuid.DEVICE_BATTERY_SERVICE_UUID.toLowerCase(),
    );

    final batteryCharacteristic = batteryService?.characteristics.firstOrNullWhere(
      (c) => c.uuid == BleUuid.DEVICE_INFORMATION_CHARACTERISTIC_BATTERY_LEVEL.toLowerCase(),
    );
    if (batteryCharacteristic != null) {
      final batteryData = await readUpstream(batteryService!.uuid, batteryCharacteristic.uuid);
      if (batteryData.isNotEmpty) {
        batteryLevel = batteryData.first;
        core.connection.signalChange(this);
      }
    }

    await handleServices(services!);
  }

  Future<void> handleServices(List<BleService> services);
  Future<void> processCharacteristic(String characteristic, Uint8List bytes);

  // ── Upstream I/O seams ────────────────────────────────────────────────
  // ProxyDevice overrides these to route through its TrainerTransport so a
  // WiFi (DirCon) trainer reuses this whole connect flow. The defaults are
  // verbatim the previous inline UniversalBle calls.

  @protected
  Future<void> connectUpstream() async {
    await UniversalBle.connect(device.deviceId);
    if (!kIsWeb) {
      try {
        await UniversalBle.requestMtu(device.deviceId, 517);
      } catch (e) {
        // not critical, just log it
        debugPrint('Failed to request MTU: $e');
      }
    }
  }

  @protected
  Future<List<BleService>> discoverUpstreamServices() => UniversalBle.discoverServices(device.deviceId);

  @protected
  Future<Uint8List> readUpstream(String serviceUuid, String characteristicUuid) =>
      UniversalBle.read(device.deviceId, serviceUuid, characteristicUuid);

  @protected
  Future<void> disconnectUpstream() => UniversalBle.disconnect(device.deviceId);

  @override
  Future<void> disconnect() async {
    services?.clear();
    await disconnectUpstream();
    super.disconnect();
  }

  String? serviceUuidForCharacteristic(String characteristicUuid) {
    return services
        ?.firstOrNullWhere((service) => service.characteristics.any((c) => c.uuid == characteristicUuid.toLowerCase()))
        ?.uuid;
  }

  @override
  List<Widget> showMetaInformation(BuildContext context, {required bool showFull}) {
    final foregroundColor = Theme.of(context).colorScheme.mutedForeground;
    const fontSize = 11.0;
    return [
      // metaRow: battery + signal
      if (batteryLevel != null || rssi != null) ...[
        if (batteryLevel != null) ...[
          Icon(
            switch (batteryLevel!) {
              >= 80 => LucideIcons.batteryFull,
              >= 60 => LucideIcons.batteryFull,
              >= 50 => LucideIcons.batteryMedium,
              >= 25 => LucideIcons.batteryLow,
              >= 10 => LucideIcons.batteryLow,
              _ => LucideIcons.batteryWarning,
            },
            size: 14,
            color: batteryLevel! < 20 ? Theme.of(context).colorScheme.destructive : foregroundColor,
          ),
          Text(
            '$batteryLevel%',
            style: TextStyle(
              fontSize: fontSize,
              color: foregroundColor,
            ),
          ),
          // SizedBox (not Gap) because this lives in a `Wrap`, and Gap looks
          // up a Flex/Scrollable ancestor for direction — which is absent
          // when the parent device-header Row flies through a Hero overlay.
          if (firmwareVersion != null || rssi != null) const SizedBox(width: 16),
        ],
        if (firmwareVersion != null &&
            (showFull || (this is ZwiftDevice && (this as ZwiftDevice).hasNewerFirmwareVersion))) ...[
          if (this is ZwiftDevice && (this as ZwiftDevice).hasNewerFirmwareVersion)
            Icon(
              Icons.warning,
              size: fontSize,
            )
          else
            Text('FW', style: TextStyle(fontSize: 10, color: foregroundColor)).inlineCode,
          Text(
            firmwareVersion!,
            style: TextStyle(
              fontSize: fontSize,
              color: foregroundColor,
            ),
          ),
          if (this is ZwiftDevice && (this as ZwiftDevice).hasNewerFirmwareVersion)
            Text(
              ' (${context.i18n.latestVersion((this as ZwiftDevice).latestFirmwareVersion!)})',
              style: TextStyle(color: foregroundColor, fontSize: fontSize),
            ),
          if (rssi != null) const SizedBox(width: 16),
        ],
        if (rssi != null)
          StreamBuilder(
            stream: core.connection.rssiConnectionStream.where((device) => device == this).map((event) => event.rssi),
            builder: (context, rssiValue) {
              final currentRssi = rssiValue.data ?? rssi!;
              if (showFull || currentRssi < -70) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.signal, size: 14, color: foregroundColor),
                    const Gap(4),
                    Text(
                      switch (currentRssi) {
                        >= -50 => 'Strong',
                        >= -70 => 'Good',
                        >= -85 => 'Fair',
                        _ => 'Weak',
                      },
                      style: TextStyle(fontSize: fontSize, color: foregroundColor),
                    ),
                  ],
                );
              } else {
                return const SizedBox.shrink();
              }
            },
          ),
      ],
    ];
  }

  void debugSubscribeToAll(List<BleService> services) {
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.properties.contains(CharacteristicProperty.indicate)) {
          debugPrint('Subscribing to indications for ${service.uuid} / ${characteristic.uuid}');
          UniversalBle.subscribeIndications(device.deviceId, service.uuid, characteristic.uuid);
        }
        if (characteristic.properties.contains(CharacteristicProperty.notify)) {
          debugPrint('Subscribing to notifications for ${service.uuid} / ${characteristic.uuid}');
          UniversalBle.subscribeNotifications(device.deviceId, service.uuid, characteristic.uuid);
        }
      }
    }
  }
}

/// Marker for devices that react to trainer/game state rather than acting as a
/// controller (e.g. Headwind fan, KICKR Climb). Excluded from [controllerDevices].
mixin Accessory on BluetoothDevice {}
