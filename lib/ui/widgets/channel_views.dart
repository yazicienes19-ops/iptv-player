import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/channel.dart';
import '../../models/channel_name.dart';
import '../../models/content_type.dart';
import '../../player/fullscreen_player_page.dart';
import '../../player/player_controller.dart';
import '../../providers/app_providers.dart';
import '../detail/detail_page.dart';
import '../theme.dart';
import 'logo_image.dart';
import 'tv_focus.dart';

/// Live-Sender laufen sofort im eingebetteten Player, Filme und Serien
/// öffnen erst ihre Detailseite. Trennzeilen sind nicht anklickbar.
void openChannel(BuildContext context, WidgetRef ref, Channel channel, List<Channel> queue) {
  if (channel.isSeparator) return;
  if (channel.type == ContentType.live) {
    ref.read(playerControllerProvider.notifier).play(channel, queue: queue);
    return;
  }
  Navigator.of(context).push(DetailPage.route(channel, queue));
}

/// Startet einen Film oder eine Folge direkt im Vollbild, an der gemerkten
/// Stelle oder mit [fromStart] von vorne.
void playFullscreen(
  BuildContext context,
  WidgetRef ref,
  Channel channel,
  List<Channel> queue, {
  bool fromStart = false,
}) {
  ref.read(playerControllerProvider.notifier).play(channel, queue: queue, fromStart: fromStart);
  Navigator.of(context).push(FullscreenPlayerPage.route());
}

// ---------------------------------------------------------------------------
// Senderliste mit haftenden Abschnittsüberschriften
// ---------------------------------------------------------------------------

class _Section {
  _Section(this.header);

  final ChannelName? header;
  final List<Channel> channels = [];
}

/// Senderliste für Live TV. Trennzeilen werden zu haftenden Überschriften und
/// zählen weder bei der Nummerierung noch beim Kanalwechsel mit.
class ChannelList extends StatelessWidget {
  const ChannelList({super.key, required this.channels, this.categoryNames = const {}, this.bottomPadding = 16});

  final List<Channel> channels;
  final Map<String, String> categoryNames;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final sections = <_Section>[_Section(null)];
    for (final channel in channels) {
      if (channel.isSeparator) {
        sections.add(_Section(channel.display));
      } else {
        sections.last.channels.add(channel);
      }
    }
    sections.removeWhere((s) => s.channels.isEmpty);
    final queue = [for (final s in sections) ...s.channels];

    var offset = 0;
    final slivers = <Widget>[];
    for (final section in sections) {
      final start = offset;
      offset += section.channels.length;
      final list = SliverFixedExtentList(
        itemExtent: ChannelTile.height,
        delegate: SliverChildBuilderDelegate((context, i) {
          final channel = section.channels[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ChannelTile(
              channel: channel,
              queue: queue,
              number: start + i + 1,
              category: categoryNames[channel.categoryId],
            ),
          );
        }, childCount: section.channels.length),
      );
      // PinnedHeaderSliver haftet nur innerhalb seiner Gruppe; der nächste
      // Abschnitt schiebt die Überschrift sauber hinaus.
      slivers.add(
        section.header == null
            ? list
            : SliverMainAxisGroup(
                slivers: [
                  PinnedHeaderSliver(
                    child: _SectionHeader(name: section.header!, count: section.channels.length),
                  ),
                  list,
                ],
              ),
      );
    }

    return CustomScrollView(
      slivers: [
        ...slivers,
        SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.name, required this.count});

  final ChannelName name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          if (name.country != null) ...[CountryTag(code: name.country!), const SizedBox(width: 8)],
          Expanded(
            child: Text(
              name.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text('$count', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Senderkachel
// ---------------------------------------------------------------------------

class ChannelTile extends ConsumerStatefulWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.queue,
    this.number,
    this.category,
    this.dense = false,
  });

  static const height = 72.0;

  final Channel channel;
  final List<Channel> queue;
  final int? number;
  final String? category;
  final bool dense;

  @override
  ConsumerState<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends ConsumerState<ChannelTile> {
  bool _hovered = false;
  bool _focused = false;

  /// Maus darüber oder per Fernbedienung/Tastatur fokussiert.
  bool get _lit => _hovered || _focused;

  @override
  Widget build(BuildContext context) => TvFocus(
    onActivate: () => openChannel(context, ref, widget.channel, widget.queue),
    onFocusChange: (v) => setState(() => _focused = v),
    onSecondary: () => ref.read(favoritesProvider.notifier).toggle(widget.channel),
    child: FocusRing(visible: _focused, radius: 12, child: _buildTile(context)),
  );

  Widget _buildTile(BuildContext context) {
    final channel = widget.channel;
    final name = channel.display;
    final playback = ref.watch(playerControllerProvider.select((s) => s.channel == channel ? s : null));
    final isPlaying = playback != null;
    final isFavorite = ref.watch(favoritesProvider.select((f) => f.contains(channel)));
    final logoSize = widget.dense ? 36.0 : 44.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: GestureDetector(
          onTap: () => openChannel(context, ref, channel, widget.queue),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isPlaying ? null : (_lit ? AppColors.surface : Colors.transparent),
              gradient: isPlaying
                  ? LinearGradient(colors: [AppColors.accent.withValues(alpha: 0.20), AppColors.surfaceHigh])
                  : null,
              border: Border.all(color: _lit && !isPlaying ? Colors.white10 : Colors.transparent),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 3,
                  height: double.infinity,
                  color: isPlaying ? AppColors.accent : Colors.transparent,
                ),
                SizedBox(
                  width: widget.number == null ? 9 : 40,
                  child: widget.number == null
                      ? null
                      : Text(
                          '${widget.number}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isPlaying ? AppColors.textPrimary : AppColors.textSecondary,
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                ),
                LogoTile(channel: channel, size: logoSize),
                const SizedBox(width: 14),
                Expanded(
                  child: _TitleBlock(name: name, playback: playback, category: widget.category, dense: widget.dense),
                ),
                if (!widget.dense)
                  for (final q in name.qualities.take(3))
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: QualityBadge(tag: q),
                    ),
                if (!widget.dense)
                  ExcludeFocus(
                    // Auf dem Fernseher: Menü-Taste statt unsichtbarem Fokusziel.
                    child: AnimatedOpacity(
                      opacity: isFavorite || _lit ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: IconButton(
                        tooltip: isFavorite ? 'Aus Favoriten entfernen' : 'Zu Favoriten',
                        icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_outline_rounded, size: 20),
                        color: isFavorite ? Colors.amber : AppColors.textSecondary,
                        onPressed: () => ref.read(favoritesProvider.notifier).toggle(channel),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.name, required this.playback, required this.category, required this.dense});

  final ChannelName name;
  final PlaybackState? playback;
  final String? category;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final isPlaying = playback != null;
    final details = [?category, ...name.notes];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: dense ? 13.5 : 14.5, fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500),
        ),
        if (!dense) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              if (isPlaying) ...[
                _LiveIndicator(active: !playback!.isLoading && !playback!.hasError),
                const SizedBox(width: 6),
                Text(
                  playback!.hasError
                      ? 'Nicht verfügbar'
                      : playback!.isLoading
                      ? 'Wird geladen …'
                      : 'LIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: playback!.hasError ? AppColors.textSecondary : AppColors.accent,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (name.country != null) ...[CountryTag(code: name.country!), const SizedBox(width: 6)],
              if (details.isNotEmpty)
                Flexible(
                  child: Text(
                    details.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Drei hüpfende Balken, solange der Sender läuft.
class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator({required this.active});

  final bool active;

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(_LiveIndicator old) {
    super.didUpdateWidget(old);
    if (widget.active && !_controller.isAnimating) _controller.repeat();
    if (!widget.active && _controller.isAnimating) _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 11,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final phase in const [0.0, 0.35, 0.7])
              Container(
                width: 2.6,
                height: widget.active ? 3 + 8 * (0.5 + 0.5 * _wave(_controller.value + phase)) : 4,
                decoration: BoxDecoration(
                  color: widget.active ? AppColors.accent : AppColors.textSecondary,
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: widget.active
                      ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.6), blurRadius: 4)]
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Dreieckswelle -1…1, ruhiger als ein Sinus mit harten Sprüngen.
  static double _wave(double t) {
    final x = t % 1.0;
    return x < 0.5 ? x * 4 - 1 : 3 - x * 4;
  }
}

// ---------------------------------------------------------------------------
// Kleine Bausteine
// ---------------------------------------------------------------------------

/// Farbcodierte Qualitäts-Pille, z. B. Gold für 4K, Lila für HEVC.
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.tag});

  final QualityTag tag;

  static Color colorOf(QualityTag tag) => switch (tag) {
    QualityTag.uhd => const Color(0xFFFFB020),
    QualityTag.fhd => const Color(0xFF4C8DFF),
    QualityTag.hd => const Color(0xFF2EC4B6),
    QualityTag.sd => const Color(0xFF8A919E),
    QualityTag.hevc => const Color(0xFFB07CFF),
    QualityTag.fps50 => const Color(0xFF3DD68C),
    QualityTag.raw => const Color(0xFFFF7A6B),
  };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Text(
        tag.label,
        style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, height: 1.2),
      ),
    );
  }
}

/// Dezentes Länder-Tag wie „DE“.
class CountryTag extends StatelessWidget {
  const CountryTag({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(4)),
      child: Text(
        code,
        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary, height: 1.2),
      ),
    );
  }
}

/// Senderlogo in dunklem Container mit feinem Rand; ohne Logo ein Monogramm.
class LogoTile extends StatelessWidget {
  const LogoTile({super.key, required this.channel, this.size = 44});

  final Channel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.logoSurface,
        borderRadius: radius,
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: LogoImage(
          url: channel.logo,
          name: channel.display.title,
          padding: const EdgeInsets.all(6),
          monogramSize: size,
        ),
      ),
    );
  }
}

/// Initialen auf einem aus dem Namen abgeleiteten, gedeckten Farbverlauf.
class Monogram extends StatelessWidget {
  const Monogram({super.key, required this.name, required this.size});

  final String name;
  final double size;

  static const _palette = [
    Color(0xFF4C5BD4),
    Color(0xFF2E8B7A),
    Color(0xFFB0563B),
    Color(0xFF8A4FBF),
    Color(0xFF3A7BBF),
    Color(0xFFB8860B),
    Color(0xFFA23E5E),
  ];

  static String initials(String name) {
    final words = name
        .split(RegExp(r'[\s\-_.]+'))
        .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9ÄÖÜäöü]').hasMatch(w));
    final letters = words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final color = _palette[name.hashCode.abs() % _palette.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.25)],
        ),
      ),
      child: Center(
        child: Text(
          initials(name),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.32, letterSpacing: 0.5),
        ),
      ),
    );
  }
}

/// Querformat-Kachel für Live-Sender in den Favoriten.
class LiveCard extends ConsumerStatefulWidget {
  const LiveCard({super.key, required this.channel, required this.queue, required this.onTap, this.width = 200});

  final Channel channel;
  final List<Channel> queue;
  final VoidCallback onTap;
  final double width;

  @override
  ConsumerState<LiveCard> createState() => _LiveCardState();
}

class _LiveCardState extends ConsumerState<LiveCard> {
  bool _hovered = false;
  bool _focused = false;

  /// Maus darüber oder per Fernbedienung/Tastatur fokussiert.
  bool get _lit => _hovered || _focused;

  @override
  Widget build(BuildContext context) =>
      TvFocus(onActivate: widget.onTap, onFocusChange: (v) => setState(() => _focused = v), child: _buildTile(context));

  Widget _buildTile(BuildContext context) {
    final isPlaying = ref.watch(playerControllerProvider.select((s) => s.channel == widget.channel));
    final name = widget.channel.display;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: _lit ? 1.04 : 1,
                duration: const Duration(milliseconds: 180),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.logoSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isPlaying ? AppColors.accent : Colors.white10,
                        width: isPlaying ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: LogoImage(url: widget.channel.logo, name: name.title, padding: const EdgeInsets.all(22)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: _lit ? AppColors.textPrimary : AppColors.textSecondary),
                    ),
                  ),
                  for (final q in name.qualities.take(2))
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: QualityBadge(tag: q),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
