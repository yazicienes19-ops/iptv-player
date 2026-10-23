import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/playlist_credentials.dart';
import '../../providers/app_providers.dart';
import '../../services/playlist_loader.dart';
import '../../services/xtream_api.dart';
import '../theme.dart';

/// Playlist hinzufügen: Xtream Codes, M3U-URL oder lokale M3U-Datei.
class AddPlaylistScreen extends ConsumerStatefulWidget {
  const AddPlaylistScreen({super.key, this.isOnboarding = false});

  final bool isOnboarding;

  @override
  ConsumerState<AddPlaylistScreen> createState() => _AddPlaylistScreenState();
}

class _AddPlaylistScreenState extends ConsumerState<AddPlaylistScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _m3uUrl = TextEditingController();

  PlaylistKind _kind = PlaylistKind.xtream;
  String? _pickedFilePath;
  String? _pickedFileName;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _server, _username, _password, _m3uUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
    );
    final file = files.singleOrNull;
    if (file?.path == null) return;
    setState(() {
      _pickedFilePath = file!.path;
      _pickedFileName = file.name;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_kind == PlaylistKind.m3uFile && _pickedFilePath == null) {
      setState(() => _error = 'Bitte eine M3U-Datei auswählen.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final fallbackName = switch (_kind) {
      PlaylistKind.xtream =>
        Uri.tryParse(_server.text.trim())?.host ?? 'Xtream',
      PlaylistKind.m3uUrl => 'M3U Playlist',
      PlaylistKind.m3uFile => _pickedFileName ?? 'Lokale Playlist',
    };
    final name = _name.text.trim().isEmpty ? fallbackName : _name.text.trim();

    try {
      final PlaylistCredentials playlist;
      switch (_kind) {
        case PlaylistKind.xtream:
          playlist = PlaylistCredentials(
            id: id,
            name: name,
            kind: _kind,
            serverUrl: _server.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
          );
          await XtreamApi(
            playlist,
            dio: ref.read(httpClientProvider),
          ).authenticate();
        case PlaylistKind.m3uUrl:
          playlist = PlaylistCredentials(
            id: id,
            name: name,
            kind: _kind,
            m3uUrl: _m3uUrl.text.trim(),
          );
        case PlaylistKind.m3uFile:
          final path = await PlaylistLoader.importFile(_pickedFilePath!, id);
          playlist = PlaylistCredentials(
            id: id,
            name: name,
            kind: _kind,
            localFilePath: path,
          );
      }

      await ref.read(playlistsProvider.notifier).add(playlist);
      if (mounted && !widget.isOnboarding) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: widget.isOnboarding
          ? null
          : AppBar(title: const Text('Playlist hinzufügen')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.isOnboarding) ...[
                      const Icon(
                        Icons.live_tv_rounded,
                        size: 56,
                        color: AppColors.accent,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Willkommen',
                        textAlign: TextAlign.center,
                        style: textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Füge deine erste Playlist hinzu, um loszulegen.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                    SegmentedButton<PlaylistKind>(
                      segments: const [
                        ButtonSegment(
                          value: PlaylistKind.xtream,
                          label: Text('Xtream'),
                          icon: Icon(Icons.dns_outlined),
                        ),
                        ButtonSegment(
                          value: PlaylistKind.m3uUrl,
                          label: Text('M3U URL'),
                          icon: Icon(Icons.link),
                        ),
                        // Im Browser gibt es keinen Dateipfad zum Kopieren.
                        if (!kIsWeb)
                          ButtonSegment(
                            value: PlaylistKind.m3uFile,
                            label: Text('Datei'),
                            icon: Icon(Icons.folder_open),
                          ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: _busy
                          ? null
                          : (s) => setState(() => _kind = s.first),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Name (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._fieldsForKind(),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _kind == PlaylistKind.xtream
                                  ? 'Anmelden'
                                  : 'Hinzufügen',
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _fieldsForKind() {
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null;

    return switch (_kind) {
      PlaylistKind.xtream => [
        TextFormField(
          controller: _server,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server-URL',
            hintText: 'http://example.com:8080',
          ),
          validator: required,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _username,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Benutzername'),
          validator: required,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passwort'),
          validator: required,
          onFieldSubmitted: (_) => _submit(),
        ),
      ],
      PlaylistKind.m3uUrl => [
        TextFormField(
          controller: _m3uUrl,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'M3U-URL',
            hintText: 'http://…/playlist.m3u',
          ),
          validator: (v) {
            final uri = Uri.tryParse(v?.trim() ?? '');
            return uri == null || !uri.hasScheme || uri.host.isEmpty
                ? 'Gültige URL eingeben'
                : null;
          },
        ),
      ],
      PlaylistKind.m3uFile => [
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickFile,
          icon: const Icon(Icons.upload_file),
          label: Text(_pickedFileName ?? 'M3U-Datei auswählen'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    };
  }
}
