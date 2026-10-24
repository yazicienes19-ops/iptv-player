import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../player/player_controller.dart';
import '../../providers/app_providers.dart';
import '../../providers/imdb_providers.dart';
import '../../services/imdb_catalog.dart';
import '../../services/app_settings.dart';
import '../../services/local_data_cleanup.dart';
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
              // Im Browser (LG-Fernseher) lässt sich kein VPN erkennen.
              if (!kIsWeb) ...[
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
              ],
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
              const _SectionTitle('Film- & Serieninfos (TMDB)'),
              const _Card(child: _TmdbKeyCard()),
              const SizedBox(height: 8),
              const Text(
                'Liefert Darsteller, Trailer, Reihen und Empfehlungen. Diese App nutzt die TMDB-API, '
                'ist aber nicht von TMDB unterstützt oder zertifiziert. TMDB sieht, zu welchen Titeln '
                'du Infos abrufst; die Abfragen laufen über User-Agent und Kill-Switch dieser App.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 28),
              if (!kIsWeb) ...[
                const _SectionTitle('IMDb-Ranglisten'),
                const _Card(child: _ImdbCatalogCard()),
                const SizedBox(height: 28),
              ],
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

  // Nur app-eigene Verzeichnisse leeren, niemals den gemeinsamen Temp-Ordner.
  if (!kIsWeb) await clearAppFiles();

  // Logos und Poster aus dem Arbeitsspeicher.
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();

  ref
    ..invalidate(playlistsProvider)
    ..invalidate(settingsProvider)
    ..invalidate(favoritesProvider)
    ..invalidate(recentChannelsProvider)
    ..invalidate(personalLibraryProvider)
    ..invalidate(languageFilterProvider)
    ..invalidate(tmdbKeyProvider)
    ..invalidate(imdbCatalogProvider)
    ..invalidate(imdbFilterProvider)
    ..invalidate(hideSeparatorsProvider)
    ..invalidate(sectionProvider)
    ..invalidate(m3uPlaylistProvider);
  ref.invalidate(catalogProvider);
  ref.invalidate(mediaDetailsProvider);
}

class _ImdbCatalogCard extends ConsumerStatefulWidget {
  const _ImdbCatalogCard();

  @override
  ConsumerState<_ImdbCatalogCard> createState() => _ImdbCatalogCardState();
}

class _ImdbCatalogCardState extends ConsumerState<_ImdbCatalogCard> {
  bool _busy = false;
  String? _error;

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selection = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
      if (!mounted) return;
      final path = selection?.path;
      if (path != null) {
        await ref.read(imdbCatalogProvider.notifier).importFile(path);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException ? error.message.toString() : 'Datei konnte nicht importiert werden.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imdbCatalogProvider);
    final catalog = state.value;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Beste Filme und Krimis aus deiner Playlist', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            catalog == null
                ? 'Importiere deinen persönlichen IMDb-Katalog als JSON. Danach erscheinen bewertete Filmreihen und Genre-Filter.'
                : '${catalog.movies.length} Filme · ab ${catalog.minVotes} Stimmen\n'
                      'Datenstand: ${catalog.generatedAt.toLocal().toIso8601String().substring(0, 10)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(
              _busy
                  ? 'Wird importiert …'
                  : catalog == null
                  ? 'IMDb-Katalog importieren'
                  : 'Katalog aktualisieren',
            ),
          ),
          if (catalog != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await ref.read(imdbCatalogProvider.notifier).clear();
                      ref.read(imdbFilterProvider.notifier).select(null);
                    },
              child: const Text('Importierten Katalog entfernen'),
            ),
          if (_error != null || state.hasError)
            Text(
              _error ?? 'Gespeicherter Katalog nicht lesbar. Bitte erneut importieren.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (catalog != null) ...[
            const SizedBox(height: 8),
            const Text(ImdbCatalog.attribution, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ],
      ),
    );
  }
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

class _TmdbKeyCard extends ConsumerStatefulWidget {
  const _TmdbKeyCard();

  @override
  ConsumerState<_TmdbKeyCard> createState() => _TmdbKeyCardState();
}

class _TmdbKeyCardState extends ConsumerState<_TmdbKeyCard> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(tmdbKeyProvider.notifier).save(_controller.text);
      _controller.clear();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(tmdbKeyProvider).value;
    final connected = key != null && key.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.check_circle_rounded : Icons.key_rounded,
                color: connected ? vpnGreen : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  connected
                      ? 'Verbunden (Schlüssel endet auf …${key.substring(key.length - 4)})'
                      : 'Kein Schlüssel hinterlegt',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (connected)
                TextButton(
                  onPressed: () => ref.read(tmdbKeyProvider.notifier).remove(),
                  child: const Text('Entfernen'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            obscureText: true,
            enabled: !_busy,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: connected ? 'Neuen Schlüssel eintragen' : 'API-Schlüssel oder Lesezugriffstoken',
              errorText: _error,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://www.themoviedb.org/settings/api'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Schlüssel anlegen'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Prüfen & speichern'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
