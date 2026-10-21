import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../models/channel.dart';
import '../../models/channel_name.dart';
import '../../models/epg_item.dart';
import '../../player/player_controller.dart';
import '../../providers/app_providers.dart';
import '../theme.dart';
import 'channel_views.dart';

String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Bereich unter dem Player: Kopfzeile, „Aktuelles Programm“ und „Stream-Info“.
class NowPlayingPanel extends ConsumerWidget {
  const NowPlayingPanel({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = channel.display;
    final playback = ref.watch(playerControllerProvider);
    final player = ref.read(playerControllerProvider.notifier).player;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 760;
        final epg = _EpgCard(channel: channel);
        final info = _StreamInfoCard(player: player, playback: playback);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                LogoTile(channel: channel, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _LiveBadge(playback: playback),
                          if (name.country != null) CountryTag(code: name.country!),
                          for (final q in name.qualities) QualityBadge(tag: q),
                          for (final note in name.notes)
                            Text(note, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (twoColumns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: epg),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: info),
                  ],
                ),
              )
            else ...[
              epg,
              const SizedBox(height: 14),
              info,
            ],
          ],
        );
      },
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.playback});

  final PlaybackState playback;

  @override
  Widget build(BuildContext context) {
    final (label, color) = playback.hasError
        ? ('OFFLINE', AppColors.textSecondary)
        : playback.isLoading
        ? ('VERBINDE …', const Color(0xFFFFB020))
        : ('LIVE', AppColors.live);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Colors.white),
      ),
    );
  }
}

/// Gemeinsamer Kartenrahmen.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aktuelles Programm
// ---------------------------------------------------------------------------

class _EpgCard extends ConsumerStatefulWidget {
  const _EpgCard({required this.channel});

  final Channel channel;

  @override
  ConsumerState<_EpgCard> createState() => _EpgCardState();
}

class _EpgCardState extends ConsumerState<_EpgCard> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Fortschrittsbalken und „noch X Min.“ laufen mit.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final epg = ref.watch(shortEpgProvider(widget.channel));
    return _Card(
      title: 'Aktuelles Programm',
      icon: Icons.calendar_view_day_rounded,
      child: epg.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => const _Hint(icon: Icons.cloud_off_rounded, text: 'Programminfo konnte nicht geladen werden.'),
        data: (items) {
          final now = DateTime.now();
          final upcoming = items.where((i) => i.end.isAfter(now)).toList();
          if (upcoming.isEmpty) {
            return const _Hint(
              icon: Icons.event_busy_rounded,
              text: 'Für diesen Sender liefert die Playlist keine Programminfo.',
            );
          }
          final current = upcoming.first.isLiveAt(now) ? upcoming.first : null;
          final next = upcoming.skip(current == null ? 0 : 1).take(2).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (current != null) _CurrentShow(item: current, now: now),
              if (next.isNotEmpty) ...[
                if (current != null) const Divider(height: 28),
                for (final item in next) _NextShow(item: item),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CurrentShow extends StatelessWidget {
  const _CurrentShow({required this.item, required this.now});

  final EpgItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final remaining = item.end.difference(now).inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'JETZT',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.accent),
        ),
        const SizedBox(height: 4),
        Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: item.progressAt(now),
            minHeight: 4,
            backgroundColor: AppColors.border,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '${_time(item.start)} – ${_time(item.end)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const Spacer(),
            Text('noch $remaining Min.', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        if (item.description?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          Text(
            item.description!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFFC4C8D0)),
          ),
        ],
      ],
    );
  }
}

class _NextShow extends StatelessWidget {
  const _NextShow({required this.item});

  final EpgItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              _time(item.start),
              style: const TextStyle(color: AppColors.textSecondary, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          const Text(
            'DANACH  ',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stream-Info
// ---------------------------------------------------------------------------

/// Technische Daten des laufenden Streams, alle 2 s direkt aus libmpv gelesen.
class _StreamInfoCard extends StatefulWidget {
  const _StreamInfoCard({required this.player, required this.playback});

  final Player player;
  final PlaybackState playback;

  @override
  State<_StreamInfoCard> createState() => _StreamInfoCardState();
}

class _StreamInfoCardState extends State<_StreamInfoCard> {
  Timer? _poll;
  Map<String, String> _props = const {};

  static const _properties = [
    'estimated-vf-fps',
    'container-fps',
    'video-format',
    'audio-codec-name',
    'video-bitrate',
    'audio-bitrate',
    'hwdec-current',
    'demuxer-cache-duration',
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final platform = widget.player.platform;
    if (platform is! NativePlayer) return;
    final values = <String, String>{};
    for (final p in _properties) {
      try {
        values[p] = await platform.getProperty(p);
      } catch (_) {
        // Eigenschaft gerade nicht verfügbar (z. B. vor dem ersten Bild).
      }
    }
    if (mounted) setState(() => _props = values);
  }

  double? _num(String key) => double.tryParse(_props[key] ?? '');

  @override
  Widget build(BuildContext context) {
    final state = widget.player.state;
    final width = state.width;
    final height = state.height;
    final running = !widget.playback.isLoading && !widget.playback.hasError && (width ?? 0) > 0;

    final fps = _num('estimated-vf-fps') ?? _num('container-fps');
    final videoBitrate = _num('video-bitrate');
    final audioBitrate = _num('audio-bitrate');
    final cache = _num('demuxer-cache-duration');
    final hw = _props['hwdec-current'];

    final rows = <(String, String)>[
      ('Auflösung', running ? '$width×$height  ·  ${_qualityLabel(height!)}' : '–'),
      ('Bildrate', fps != null && fps > 0 ? '${_formatFps(fps)} fps' : '–'),
      ('Video', _videoCodec(_props['video-format']) ?? '–'),
      ('Audio', _audioCodec(_props['audio-codec-name']) ?? '–'),
      ('Bitrate', _formatBitrate(videoBitrate, audioBitrate) ?? '–'),
      ('Dekodierung', hw == null || hw.isEmpty || hw == 'no' ? 'Software' : 'Hardware ($hw)'),
      ('Puffer', cache != null ? '${cache.toStringAsFixed(1)} s' : '–'),
    ];

    return _Card(
      title: 'Stream-Info',
      icon: Icons.insights_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            'TONSPUR',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          _AudioTrackSelector(player: widget.player),
        ],
      ),
    );
  }

  static String _qualityLabel(int height) => switch (height) {
    >= 2000 => '4K',
    >= 1000 => 'Full HD',
    >= 700 => 'HD',
    _ => 'SD',
  };

  static String _formatFps(double fps) {
    final rounded = fps.roundToDouble();
    return (fps - rounded).abs() < 0.05 ? rounded.toStringAsFixed(0) : fps.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String? _formatBitrate(double? video, double? audio) {
    final total = (video ?? 0) + (audio ?? 0);
    if (total <= 0) return null;
    return total >= 1e6
        ? '${(total / 1e6).toStringAsFixed(1).replaceAll('.', ',')} Mbit/s'
        : '${(total / 1e3).round()} kbit/s';
  }

  static String? _videoCodec(String? format) => switch (format) {
    null || '' => null,
    'h264' => 'H.264 / AVC',
    'hevc' => 'H.265 / HEVC',
    'av1' => 'AV1',
    'vp9' => 'VP9',
    'mpeg2video' => 'MPEG-2',
    _ => format.toUpperCase(),
  };

  static String? _audioCodec(String? codec) => switch (codec) {
    null || '' => null,
    'aac' => 'AAC',
    'ac3' => 'Dolby Digital (AC-3)',
    'eac3' => 'Dolby Digital Plus',
    'mp2' => 'MPEG Audio (MP2)',
    'mp3' => 'MP3',
    'opus' => 'Opus',
    _ => codec.toUpperCase(),
  };
}

class _AudioTrackSelector extends StatelessWidget {
  const _AudioTrackSelector({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Track>(
      stream: player.stream.track,
      initialData: player.state.track,
      builder: (context, _) => StreamBuilder<Tracks>(
        stream: player.stream.tracks,
        initialData: player.state.tracks,
        builder: (context, snapshot) {
          final tracks = (snapshot.data?.audio ?? const <AudioTrack>[])
              .where((t) => t.id != 'auto' && t.id != 'no')
              .toList();
          final active = player.state.track.audio;
          if (tracks.isEmpty) {
            return const Text('–', style: TextStyle(color: AppColors.textSecondary));
          }
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, t) in tracks.indexed)
                ChoiceChip(
                  label: Text(
                    t.title ?? t.language?.toUpperCase() ?? 'Spur ${i + 1}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                  // „auto“ bedeutet: libmpv hat die erste Spur gewählt.
                  selected: t == active || (active.id == 'auto' && i == 0),
                  onSelected: (_) => player.setAudioTrack(t),
                ),
            ],
          );
        },
      ),
    );
  }
}
