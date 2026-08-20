import 'dart:io' show Platform;

import 'package:bike_control/main.dart' show recordError;
import 'package:bike_control/services/mdns_discovery_scan.dart';
import 'package:flutter/foundation.dart';
import 'package:prop/mdns/service_advertiser.dart';
import 'package:prop/utils/advertised_service_registry.dart';
import 'package:prop/utils/network_address.dart';
import 'package:prop/utils/resilient_tcp_server.dart';

/// A running TCP bridge server, for diagnostics.
class TcpServerInfo {
  final String? label;
  final int? port;
  final bool listening;
  final bool hasClient;

  const TcpServerInfo({
    required this.label,
    required this.port,
    required this.listening,
    required this.hasClient,
  });
}

/// Status of the permissions whose denial silently breaks WiFi/BLE bridging.
class PermissionsSnapshot {
  /// iOS Local Network can't be queried directly; inferred from whether a
  /// discovery scan returned anything. Null when no scan ran.
  final bool? localNetworkInferred;

  const PermissionsSnapshot({
    required this.localNetworkInferred,
  });

  static Future<PermissionsSnapshot> gather({bool? localNetworkInferred}) async {
    return PermissionsSnapshot(
      localNetworkInferred: localNetworkInferred,
    );
  }
}

/// The full diagnostics snapshot shown on the Logs page and embedded in
/// [debugText]. Build with [gather]; render with [toText].
class DebugDiagnostics {
  final List<AdvertisedRecord> advertised;
  final String backend;
  final String? hostLabel;
  final bool holdsMulticastLock;
  final List<DiscoveredMdnsService> discovered;
  final bool discoveryRan;
  final AddressPickReport addressReport;
  final List<TcpServerInfo> servers;
  final PermissionsSnapshot permissions;

  const DebugDiagnostics({
    required this.advertised,
    required this.backend,
    required this.hostLabel,
    required this.holdsMulticastLock,
    required this.discovered,
    required this.discoveryRan,
    required this.addressReport,
    required this.servers,
    required this.permissions,
  });

  static Future<DebugDiagnostics> gather({
    bool includeDiscovery = true,
    Duration discoveryTimeout = const Duration(seconds: 4),
  }) async {
    final advertiser = ServiceAdvertiser.instance;
    final isResponder = advertiser is ResponderServiceAdvertiser;

    AddressPickReport addressReport;
    try {
      addressReport = await AdvertisedAddressPicker.report();
    } catch (e, s) {
      recordError(e, s, context: 'DebugDiagnostics.address');
      addressReport = const AddressPickReport(chosen: null, candidates: []);
    }

    final servers = ResilientTcpServer.activeServers
        .map(
          (s) => TcpServerInfo(
            label: s.label,
            port: s.isRunning ? s.boundPort : null,
            listening: s.isRunning,
            hasClient: s.hasClient,
          ),
        )
        .toList();

    var discovered = <DiscoveredMdnsService>[];
    var discoveryRan = false;
    if (includeDiscovery && !kIsWeb) {
      try {
        discovered = await MdnsDiscoveryScan().run(timeout: discoveryTimeout);
        discoveryRan = true;
      } catch (e, s) {
        recordError(e, s, context: 'DebugDiagnostics.discovery');
      }
    }

    final permissions = await PermissionsSnapshot.gather(
      // iOS is the only platform with a (non-queryable) "Local Network"
      // permission; infer it from whether discovery saw anything. Elsewhere an
      // empty scan just means no peers, so leave it unset.
      localNetworkInferred: (discoveryRan && !kIsWeb && Platform.isIOS) ? discovered.isNotEmpty : null,
    );

    return DebugDiagnostics(
      advertised: AdvertisedServiceRegistry.instance.records,
      backend: isResponder ? 'responder' : 'nsd',
      hostLabel: isResponder ? advertiser.hostLabel : null,
      holdsMulticastLock: isResponder ? advertiser.holdsMulticastLock : false,
      discovered: discovered,
      discoveryRan: discoveryRan,
      addressReport: addressReport,
      servers: servers,
      permissions: permissions,
    );
  }

  /// Name fragments that mean "VPN tunnel" — the VPN subset of the address
  /// picker's broader "virtual" set, which also covers docker bridges, the
  /// Personal Hotspot bridge and cellular interfaces (none of them a VPN).
  ///
  /// Matched case-insensitively, and partly as a substring, because on Windows
  /// `NetworkInterface.name` is the adapter's FriendlyName ("NordLynx",
  /// "ProtonVPN TUN", "TAP-Windows Adapter V9") rather than a unix device
  /// name, so prefix matching alone would miss nearly every Windows VPN.
  static final _tunnelNamePattern = RegExp(
    r'^(utun|tun|tap|ipsec|ppp|wg|nordlynx|zt)'
    r'|wireguard|openvpn|tailscale|zerotier|mullvad|proton|anyconnect|vpn|tunnel',
    caseSensitive: false,
  );

  /// 169.254/16 is link-local and 192.0.0/24 is the 464XLAT CLAT dummy range;
  /// neither is ever a VPN, and both show up on healthy devices.
  static bool _isRoutable(String address) =>
      !address.startsWith('169.254.') && !address.startsWith('192.0.0.');

  /// 100.64/10, the CGNAT range mesh VPNs (Tailscale, ZeroTier) hand out.
  static bool _isCgnat(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null)) return false;
    return parts[0] == 100 && parts[1]! >= 64 && parts[1]! <= 127;
  }

  /// Tunnel interfaces that carry a real IPv4 — i.e. the ones a VPN actually
  /// brought up.
  ///
  /// Apple platforms always keep several idle `utun` devices around (iCloud
  /// Private Relay, Continuity, Wi-Fi Calling, content filters). Those carry
  /// only an IPv6 link-local, so they never become an [AddressCandidate] in
  /// the first place — which is what stops this from firing on every iPhone.
  List<AddressCandidate> get tunnelCandidates => addressReport.candidates
      .where((c) => _tunnelNamePattern.hasMatch(c.interfaceName) && _isRoutable(c.address))
      .toList();

  String _txt(Map<String, String> txt) {
    final entries = txt.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key}=${e.value}').join(', ');
  }

  String toText() {
    final b = StringBuffer();
    b.writeln('Diagnostics:');

    b.writeln('  Advertised by this device:');
    if (advertised.isEmpty) {
      b.writeln('    (none)');
    } else {
      for (final a in advertised) {
        b.writeln('    ${a.type} "${a.name}" ${a.address}:${a.port}');
        if (a.txt.isNotEmpty) b.writeln('      txt: ${_txt(a.txt)}');
      }
    }
    b.writeln(
      '    backend: $backend'
      '${hostLabel != null ? ' · host: $hostLabel.local' : ''}'
      '${backend == 'responder' ? ' · multicast-lock: ${holdsMulticastLock ? 'held' : 'not held'}' : ''}',
    );

    b.writeln('  Discovered on network:');
    if (!discoveryRan) {
      b.writeln('    (skipped)');
    } else if (discovered.isEmpty) {
      b.writeln('    (none found)');
    } else {
      for (final d in discovered) {
        b.writeln('    ${d.type} "${d.name}" ${d.host}:${d.port}${d.isSelf ? '  (this device)' : ''}');
        if (d.txt.isNotEmpty) b.writeln('      txt: ${_txt(d.txt)}');
      }
    }

    b.writeln('  Network interfaces (advertised = ${addressReport.chosen?.address ?? 'none'}):');
    for (final c in addressReport.candidates) {
      final tags = [
        if (addressReport.chosen?.address == c.address) 'advertised',
        if (c.isVirtual) 'virtual',
      ];
      b.writeln('    ${c.interfaceName}/${c.address} = ${c.score}${tags.isEmpty ? '' : ' (${tags.join(', ')})'}');
    }

    // Its own line, spelled "VPN", because support reads this block at a
    // glance and a "(virtual)" suffix on one of five interface rows does not
    // survive that. A live VPN leaves mDNS working (multicast is not tunnelled)
    // while blackholing the inbound TCP connection, so the rest of the block
    // looks perfectly healthy — advertised, discovered, listening, no client.
    final tunnels = tunnelCandidates;
    if (tunnels.isEmpty) {
      b.writeln('  VPN: none detected');
    } else {
      // Mesh VPNs route only their own overlay and leave the LAN path alone,
      // so they are almost never why a trainer app cannot connect.
      final meshOnly = tunnels.every((c) => _isCgnat(c.address));
      b.writeln(
        '  VPN: likely active — ${tunnels.map((c) => '${c.interfaceName}/${c.address}').join(', ')}'
        '${meshOnly ? ' (mesh/CGNAT range — usually harmless)' : ' (a full-tunnel VPN blocks inbound LAN connections — try turning it off)'}',
      );
    }

    b.writeln('  TCP servers:');
    if (servers.isEmpty) {
      b.writeln('    (none)');
    } else {
      for (final s in servers) {
        b.writeln(
          '    ${s.label ?? 'tcp'} :${s.port ?? '-'} '
          '${s.listening ? 'listening' : 'down'} · ${s.hasClient ? '1 client' : 'no client'}',
        );
      }
    }

    if (permissions.localNetworkInferred != null) {
      b.writeln(
        '  Permissions: ios-local-network='
        '${permissions.localNetworkInferred! ? 'inferred-ok' : 'inferred-blocked'}',
      );
    }

    return b.toString().trimRight();
  }
}
