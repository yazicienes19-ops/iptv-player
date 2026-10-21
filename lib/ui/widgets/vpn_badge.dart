import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../theme.dart';

const vpnGreen = Color(0xFF34C759);
const vpnYellow = Color(0xFFFFC233);

/// Dezentes VPN-Abzeichen: grünes Schild bei aktivem Tunnel, sonst gelbe Warnung.
class VpnBadge extends ConsumerWidget {
  const VpnBadge({super.key, this.iconOnly = false});

  /// Nur das Symbol (für die schmale Kopfzeile auf dem Handy).
  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(vpnStatusProvider);
    final blocked = ref.watch(networkBlockedProvider);
    final active = status.value?.active ?? false;
    final checking = status.isLoading && !status.hasValue;

    final (icon, color, label) = checking
        ? (Icons.shield_outlined, AppColors.textSecondary, 'VPN wird geprüft …')
        : active
        ? (Icons.verified_user_rounded, vpnGreen, 'VPN Aktiv (Geschützt)')
        : (Icons.gpp_maybe_rounded, vpnYellow, 'Direkte Verbindung (Kein VPN)');
    final tooltip = [
      label,
      if (active && status.value?.interfaceName != null) 'Tunnel: ${status.value!.interfaceName}',
      if (blocked) 'Kill-Switch blockiert alle Verbindungen',
    ].join('\n');

    if (iconOnly) {
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 22),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ),
            if (blocked) const Icon(Icons.block_rounded, size: 16, color: AppColors.live),
          ],
        ),
      ),
    );
  }
}
