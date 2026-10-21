import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../player/player_controller.dart';
import '../../providers/app_providers.dart';
import '../../services/app_settings.dart';
import '../theme.dart';
import '../widgets/vpn_badge.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const SettingsPage());

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _customAgent;

  @override
  void initState() {
    super.initState();
    // Nicht „late“ beim ersten Zugriff anlegen: Der könnte sonst erst in
    // dispose() passieren, wo `ref` nicht mehr benutzbar ist.
    _customAgent = TextEditingController(text: ref.read(settingsProvider).customUserAgent);
  }

  @override
  void dispose() {
    _customAgent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final vpn = ref.watch(vpnStatusProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              const _SectionTitle('Netzwerk & VPN'),
              const VpnBadge(),
              const SizedBox(height: 12),
              _Card(
                child: SwitchListTile(
                  value: settings.killSwitch,
                  onChanged: (v) => notifier.update((s) => s.copyWith(killSwitch: v)),
                  title: const Text('Streaming ohne VPN blockieren (Kill-Switch)'),
                  subtitle: Text(
                    settings.killSwitch && !(vpn?.active ?? false)
                        ? 'Aktiv: Gerade ist kein VPN verbunden, daher sind alle Verbindungen gesperrt.'
                        : 'Ohne erkanntes VPN werden weder Playlists geladen noch Streams oder Bilder abgerufen. '
                              'Bricht das VPN ab, stoppt die Wiedergabe sofort.',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Die Erkennung prüft alle 3 Sekunden, ob ein Tunnel (WireGuard, OpenVPN, IPsec …) eine Adresse hat. '
                'Bei „Split Tunneling“ kann ein VPN aktiv sein, ohne dass diese App darüber läuft.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 28),
              const _SectionTitle('Tarnung (User-Agent)'),
              _Card(
                child: RadioGroup<UserAgentPreset>(
                  groupValue: settings.userAgentPreset,
                  onChanged: (v) => notifier.update((s) => s.copyWith(userAgentPreset: v)),
                  child: Column(
                    children: [
                      for (final preset in UserAgentPreset.values)
                        RadioListTile<UserAgentPreset>(
                          value: preset,
                          title: Text(preset.label),
                          subtitle: preset.value.isEmpty
                              ? null
                              : Text(
                                  preset.value,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                        ),
                      if (settings.userAgentPreset == UserAgentPreset.custom)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: TextField(
                            controller: _customAgent,
                            decoration: const InputDecoration(hintText: 'Eigener User-Agent'),
                            onChanged: (v) => notifier.update((s) => s.copyWith(customUserAgent: v)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Gesendet wird: ${settings.userAgent}\n'
                'Gilt für Playlists, Programminfo, Logos und den Videoplayer. '
                'Die App sendet keinerlei Nutzungsdaten oder Telemetrie.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 28),
              const _SectionTitle('Daten'),
              _Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Entfernt Playlists, Zugangsdaten aus dem Schlüsselbund, Favoriten, Einstellungen, '
                        'importierte Dateien und zwischengespeicherte Logos. Die App startet danach wie neu.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD70015),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.delete_forever_rounded),
                        label: const Text('Alle lokalen Daten & Cache sofort löschen'),
                        onPressed: () => _confirmWipe(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wirklich alles löschen?'),
        content: const Text('Alle Playlists, Zugangsdaten und Favoriten werden unwiderruflich entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD70015)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Alles löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await wipeAllLocalData(ref);
    navigator.popUntil((route) => route.isFirst);
  }
}

/// Panik-Knopf: entfernt alle Spuren der App auf diesem Gerät.
Future<void> wipeAllLocalData(WidgetRef ref) async {
  await ref.read(playerControllerProvider.notifier).stop();
  await ref.read(localStoreProvider).wipe();

  // Importierte Playlists, Zwischenspeicher und temporäre Dateien.
  final dirs = await Future.wait([
    getApplicationSupportDirectory(),
    getApplicationCacheDirectory(),
    getTemporaryDirectory(),
  ]);
  for (final dir in dirs) {
    if (!await dir.exists()) continue;
    await for (final entry in dir.list()) {
      try {
        await entry.delete(recursive: true);
      } on FileSystemException {
        // Vom System gesperrte Einträge überspringen.
      }
    }
  }

  // Logos und Poster aus dem Arbeitsspeicher.
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();

  ref
    ..invalidate(playlistsProvider)
    ..invalidate(settingsProvider)
    ..invalidate(favoritesProvider)
    ..invalidate(hideSeparatorsProvider)
    ..invalidate(sectionProvider)
    ..invalidate(m3uPlaylistProvider);
  ref.invalidate(catalogProvider);
  ref.invalidate(mediaDetailsProvider);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          letterSpacing: 1,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material statt Container: ListTiles malen Hintergrund und Klick-Welle darauf.
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white10),
      ),
      child: child,
    );
  }
}
