import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Ergebnis der VPN-Erkennung.
class VpnStatus {
  const VpnStatus({required this.active, this.interfaceName});

  static const unknown = VpnStatus(active: false);

  final bool active;

  /// z. B. `utun4`, `tun0`, `wg0`.
  final String? interfaceName;

  @override
  bool operator ==(Object other) =>
      other is VpnStatus && other.active == active && other.interfaceName == interfaceName;

  @override
  int get hashCode => Object.hash(active, interfaceName);
}

/// Wird geworfen, wenn der Kill-Switch eine Verbindung ohne VPN verhindert.
class KillSwitchException implements Exception {
  const KillSwitchException();

  @override
  String toString() => 'Kill-Switch aktiv: Kein VPN erkannt. Verbindung blockiert.';
}

/// Erkennt aktive VPN-Tunnel anhand der Netzwerk-Interfaces.
///
/// macOS legt auch ohne VPN mehrere `utun`-Interfaces an (iCloud,
/// Systemdienste), die aber nur link-lokale Adressen (`fe80::`) tragen.
/// Ein Tunnel zählt deshalb erst als VPN, wenn er eine echte Adresse hat.
class NetworkSecurityService {
  const NetworkSecurityService();

  static final _tunnelName = RegExp(
    r'^(utun|tun|tap|ppp|wg|ipsec|gpd|nordlynx|proton|mullvad)|wireguard|openvpn|vpn|tap-windows',
    caseSensitive: false,
  );

  Future<VpnStatus> detect() async {
    // Im Browser sind die Netzwerk-Interfaces nicht sichtbar.
    if (kIsWeb) return VpnStatus.unknown;
    try {
      // includeLinkLocal: false blendet fe80::/169.254.x.x bereits aus.
      final interfaces = await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false);
      for (final interface in interfaces) {
        if (!_tunnelName.hasMatch(interface.name)) continue;
        if (interface.addresses.any(_isRoutable)) {
          return VpnStatus(active: true, interfaceName: interface.name);
        }
      }
    } on SocketException {
      // Ohne Netzwerkinfo lieber „kein VPN“ melden: Der Kill-Switch blockiert dann.
    }
    return const VpnStatus(active: false);
  }

  static bool _isRoutable(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return false;
    final raw = address.address.toLowerCase();
    return !raw.startsWith('fe80') && !raw.startsWith('169.254.');
  }

  /// Prüft regelmäßig und meldet nur Änderungen.
  Stream<VpnStatus> watch({Duration interval = const Duration(seconds: 3)}) async* {
    VpnStatus? last;
    while (true) {
      final status = await detect();
      if (status != last) {
        last = status;
        yield status;
      }
      await Future<void>.delayed(interval);
    }
  }
}

/// Erzwingt den Kill-Switch vor jeder Netzwerkverbindung.
class NetworkGuard {
  const NetworkGuard({required this.killSwitch, this.service = const NetworkSecurityService()});

  final bool killSwitch;
  final NetworkSecurityService service;

  /// Prüft frisch statt aus einem Zwischenstand, damit ein gerade
  /// abgebrochenes VPN sofort auffällt.
  Future<void> ensureAllowed() async {
    if (!killSwitch || kIsWeb) return;
    if (!(await service.detect()).active) throw const KillSwitchException();
  }
}
