import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/channel.dart';
import '../../models/channel_name.dart';
import '../../models/content_type.dart';
import '../../models/language.dart';
import '../../player/fullscreen_player_page.dart';
import '../../player/player_controller.dart';
import '../../player/player_view.dart';
import '../../providers/app_providers.dart';
import '../theme.dart';
import '../widgets/channel_views.dart';
import '../widgets/common.dart';
import '../widgets/logo_image.dart';
import '../widgets/now_playing_panel.dart';
import '../widgets/tv_focus.dart';

const _weekdays = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const _months = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

/// Live TV im Breitformat: Kachel-Raster statt Senderliste.
///
/// Läuft ein Sender, stehen Player und Infos oben fest; darunter bleibt das
/// Raster zum schnellen Umschalten. Sonst zeigt der Kopf Uhr, „Weiterschauen“
/// und beliebte Sender.
class LiveWorkspace extends ConsumerWidget {
  const LiveWorkspace({super.key});

  static const padding = 32.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playerControllerProvider.select((s) => s.channel));
    final channels = ref.watch(visibleChannelsProvider(ContentType.live));
    final category = ref.watch(selectedCategoryProvider(ContentType.live));
    final searching = ref.watch(searchQueryProvider(AppSection.live)).trim().isNotEmpty;
    final showDashboard = playing == null && category == null && !searching;

    final grid = channels.when(
      loading: () => [const SliverFillRemaining(child: AsyncStateView.loading())],
      error: (e, _) => [
        SliverFillRemaining(
          child: AsyncStateView.error(
            error: e,
            onRetry: () {
              ref.invalidate(m3uPlaylistProvider);
              ref.invalidate(catalogProvider(ContentType.live));
            },
          ),
        ),
      ],
      data: (list) => list.isEmpty
          ? [
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyView(icon: Icons.search_off_rounded, message: 'Keine Sender gefunden.'),
              ),
            ]
          : _channelSections(list, title: showDashboard ? 'Alle Sender' : null),
    );

    final scroll = CustomScrollView(
      slivers: [
        if (playing == null) const SliverToBoxAdapter(child: _ClockHeader()),
        if (showDashboard) ...const [_ResumeSection(), _PopularSection()],
        const PinnedHeaderSliver(child: _Toolbar()),
        ...grid,
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.6, -1),
          radius: 1.4,
          colors: [Color(0xFF1A1218), AppColors.background],
        ),
      ),
      child: SafeArea(
        left: false,
        child: playing == null
            ? scroll
            : Column(
                children: [
                  _PlayerHeader(channel: playing),
                  Expanded(child: scroll),
                ],
              ),
      ),
    );
  }

  /// Raster je Abschnitt; Trennzeilen („----- SPORT -----“) werden Überschriften.
  static List<Widget> _channelSections(List<Channel> channels, {String? title}) {
    final sections = <(ChannelName?, List<Channel>)>[(null, [])];
    for (final channel in channels) {
      if (channel.isSeparator) {
        sections.add((channel.display, []));
      } else {
        sections.last.$2.add(channel);
      }
    }
    sections.removeWhere((s) => s.$2.isEmpty);
    final queue = [for (final s in sections) ...s.$2];

    return [
      if (title != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(padding, 8, padding, 4),
            child: _SectionTitle(icon: Icons.grid_view_rounded, title: title),
          ),
        ),
      for (final (header, items) in sections)
        SliverMainAxisGroup(
          slivers: [
            if (header != null)
              PinnedHeaderSliver(
                child: _GroupHeader(name: header, count: items.length),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(padding, 12, padding, 16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 168,
                  childAspectRatio: 0.98,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => ChannelGridTile(channel: items[i], queue: queue),
              ),
            ),
          ],
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Kopfbereiche
// ---------------------------------------------------------------------------

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        // Player nimmt gut die Hälfte der Breite, höchstens 55 % der Höhe.
        final playerWidth = (constraints.maxWidth - LiveWorkspace.padding * 2) * 0.58;
        final height = (playerWidth * 9 / 16).clamp(200.0, screenHeight * 0.55);
        return Padding(
          padding: const EdgeInsets.fromLTRB(LiveWorkspace.padding, 20, LiveWorkspace.padding, 8),
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: height * 16 / 9,
                    child: PlayerView(
                      onToggleFullscreen: () => Navigator.of(context).push(FullscreenPlayerPage.route()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NowPlayingPanel(key: ValueKey(channel.id), channel: channel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClockHeader extends StatefulWidget {
  const _ClockHeader();

  @override
  State<_ClockHeader> createState() => _ClockHeaderState();
}

class _ClockHeaderState extends State<_ClockHeader> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(LiveWorkspace.padding, 28, LiveWorkspace.padding, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_weekdays[now.weekday - 1]}, ${now.day}. ${_months[now.month - 1]}'.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Live TV',
                  style: Theme.of(context).textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w200,
              letterSpacing: -1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Suche, Senderzahl und Trennzeilen-Schalter; haftet beim Scrollen oben.
class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(selectedCategoryProvider(ContentType.live));
    final searching = ref.watch(searchQueryProvider(AppSection.live)).trim().isNotEmpty;
    final hideSeparators = ref.watch(hideSeparatorsProvider);
    final count = searching
        ? ref.watch(visibleChannelsProvider(ContentType.live)).value?.where((c) => !c.isSeparator).length ?? 0
        : ref.watch(categoryCountsProvider(ContentType.live))[category?.id] ?? 0;

    return Container(
      color: AppColors.background.withValues(alpha: 0.94),
      padding: const EdgeInsets.fromLTRB(LiveWorkspace.padding, 10, LiveWorkspace.padding - 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  category?.name ?? 'Alle Sender',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text('$count Sender', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 340, child: SearchField(section: AppSection.live)),
          const SizedBox(width: 4),
          IconButton(
            tooltip: hideSeparators ? 'Abschnitts-Trennzeilen anzeigen' : 'Abschnitts-Trennzeilen ausblenden',
            icon: Icon(
              hideSeparators ? Icons.grid_view_rounded : Icons.view_agenda_outlined,
              color: hideSeparators ? AppColors.textSecondary : AppColors.textPrimary,
            ),
            onPressed: () => ref.read(hideSeparatorsProvider.notifier).toggle(),
          ),
        ],
      ),
    );
  }
}

class _ResumeSection extends ConsumerWidget {
  const _ResumeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentChannelsProvider);
    if (recents.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: LiveWorkspace.padding),
              child: _SectionTitle(icon: Icons.history_rounded, title: 'Weiterschauen'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: LiveWorkspace.padding),
                itemCount: recents.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) => _ResumeCard(
                  channel: recents[i],
                  isLast: i == 0,
                  onTap: () => ref.read(playerControllerProvider.notifier).play(recents[i], queue: recents),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularSection extends ConsumerWidget {
  const _PopularSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final popular = ref.watch(popularLiveChannelsProvider);
    final language = Language.byCode(ref.watch(languageFilterProvider));
    if (popular.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: LiveWorkspace.padding),
            child: _SectionTitle(
              icon: Icons.local_fire_department_rounded,
              title: language == null ? 'Beliebte Sender' : 'Beliebte Sender · ${language.flag} ${language.label}',
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(LiveWorkspace.padding, 14, LiveWorkspace.padding, 30),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 168,
              childAspectRatio: 0.98,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
            ),
            itemCount: popular.length,
            itemBuilder: (context, i) => ChannelGridTile(channel: popular[i], queue: popular),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.name, required this.count});

  final ChannelName name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: AppColors.background.withValues(alpha: 0.94),
      padding: const EdgeInsets.fromLTRB(LiveWorkspace.padding, 12, LiveWorkspace.padding, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          if (name.country != null) ...[CountryTag(code: name.country!), const SizedBox(width: 8)],
          Expanded(
            child: Text(
              name.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4),
            ),
          ),
          Text('$count', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kacheln
// ---------------------------------------------------------------------------

/// Große Senderkachel mit Logo, Name und Qualität. Der laufende Sender
/// leuchtet rot; Menü-Taste bzw. „F“ setzt ihn auf die Favoritenliste.
class ChannelGridTile extends ConsumerStatefulWidget {
  const ChannelGridTile({super.key, required this.channel, required this.queue});

  final Channel channel;
  final List<Channel> queue;

  @override
  ConsumerState<ChannelGridTile> createState() => _ChannelGridTileState();
}

class _ChannelGridTileState extends ConsumerState<ChannelGridTile> {
  bool _hovered = false;
  bool _focused = false;

  void _play() => ref.read(playerControllerProvider.notifier).play(widget.channel, queue: widget.queue);

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final name = channel.display;
    final isPlaying = ref.watch(playerControllerProvider.select((s) => s.channel == channel));
    final isFavorite = ref.watch(favoritesProvider.select((f) => f.contains(channel)));
    final lit = _hovered || _focused;

    return TvFocus(
      onActivate: _play,
      onSecondary: () => ref.read(favoritesProvider.notifier).toggle(channel),
      onFocusChange: (v) => setState(() => _focused = v),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _play,
          child: AnimatedScale(
            scale: lit ? 1.05 : 1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: Column(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.logoSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isPlaying
                            ? AppColors.accent
                            : _focused
                            ? Colors.white
                            : Colors.white.withValues(alpha: lit ? 0.2 : 0.08),
                        width: isPlaying || _focused ? 2 : 1,
                      ),
                      boxShadow: [
                        if (isPlaying) BoxShadow(color: AppColors.accent.withValues(alpha: 0.45), blurRadius: 18),
                        if (lit) const BoxShadow(color: Color(0x88000000), blurRadius: 16, offset: Offset(0, 8)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          LogoImage(
                            url: channel.logo,
                            name: name.title,
                            padding: const EdgeInsets.all(20),
                            monogramSize: 72,
                          ),
                          if (name.qualities.isNotEmpty)
                            Positioned(top: 8, right: 8, child: QualityBadge(tag: name.qualities.first)),
                          if (isFavorite)
                            const Positioned(
                              top: 7,
                              left: 8,
                              child: Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                            ),
                          if (isPlaying)
                            Positioned(
                              left: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.live,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                ),
                              ),
                            ),
                          // Stern zum Merken; per Fernbedienung über die Menü-Taste.
                          if (_hovered)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: ExcludeFocus(
                                child: IconButton(
                                  tooltip: isFavorite ? 'Aus Favoriten entfernen' : 'Zu Favoriten',
                                  iconSize: 18,
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_outline_rounded),
                                  color: isFavorite ? Colors.amber : Colors.white70,
                                  onPressed: () => ref.read(favoritesProvider.notifier).toggle(channel),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500,
                    color: isPlaying || lit ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Karte zum direkten Fortsetzen eines zuletzt gesehenen Senders.
class _ResumeCard extends StatefulWidget {
  const _ResumeCard({required this.channel, required this.isLast, required this.onTap});

  final Channel channel;
  final bool isLast;
  final VoidCallback onTap;

  @override
  State<_ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends State<_ResumeCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _focused;
    final name = widget.channel.display;
    return TvFocus(
      onActivate: widget.onTap,
      onFocusChange: (v) => setState(() => _focused = v),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: lit ? 1.03 : 1,
            duration: const Duration(milliseconds: 160),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 250,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: lit ? 0.12 : 0.07),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _focused ? Colors.white : Colors.white.withValues(alpha: 0.08),
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  LogoTile(channel: widget.channel, size: 60),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.2),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              lit ? Icons.play_circle_fill_rounded : Icons.play_circle_outline_rounded,
                              size: 17,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.isLast ? 'Zuletzt gesehen' : 'Fortsetzen',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
