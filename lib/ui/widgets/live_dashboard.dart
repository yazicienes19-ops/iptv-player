import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/channel.dart';
import '../../models/channel_name.dart';
import '../../models/content_type.dart';
import '../../models/language.dart';
import '../../player/player_controller.dart';
import '../../providers/app_providers.dart';
import '../theme.dart';
import 'channel_views.dart';
import 'media_image.dart';
import 'tv_focus.dart';

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

/// Rechte Seite im Live-TV-Tab, solange noch kein Sender läuft:
/// „Weiterschauen“ und beliebte Sender als Logo-Raster.
class LiveDashboard extends ConsumerWidget {
  const LiveDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentChannelsProvider);
    final popular = ref.watch(popularLiveChannelsProvider);
    final language = Language.byCode(ref.watch(languageFilterProvider));
    final queue = ref.watch(visibleChannelsProvider(ContentType.live)).value ?? const <Channel>[];

    void play(Channel channel) => ref.read(playerControllerProvider.notifier).play(channel, queue: queue);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.6, -1),
          radius: 1.4,
          colors: [Color(0xFF1A1218), AppColors.background],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
        children: [
          const _Header(),
          const SizedBox(height: 32),
          if (recents.isNotEmpty) ...[
            const _SectionTitle(icon: Icons.history_rounded, title: 'Weiterschauen'),
            const SizedBox(height: 14),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: recents.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) => _ResumeCard(
                  channel: recents[i],
                  isLast: i == 0,
                  onTap: () => ref.read(playerControllerProvider.notifier).play(recents[i], queue: recents),
                ),
              ),
            ),
            const SizedBox(height: 34),
          ],
          _SectionTitle(
            icon: Icons.local_fire_department_rounded,
            title: language == null ? 'Beliebte Sender' : 'Beliebte Sender · ${language.flag} ${language.label}',
          ),
          const SizedBox(height: 14),
          if (popular.isEmpty)
            const Text(
              'Für diese Sprache wurden keine Sender gefunden.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                childAspectRatio: 1.05,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
              ),
              itemCount: popular.length,
              itemBuilder: (context, i) => _LogoTileButton(channel: popular[i], onTap: () => play(popular[i])),
            ),
          const SizedBox(height: 28),
          const _Hint(),
        ],
      ),
    );
  }
}

class _Header extends StatefulWidget {
  const _Header();

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
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
    return Row(
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
              const SizedBox(height: 4),
              const Text(
                'Wähle links einen Sender oder starte direkt hier.',
                style: TextStyle(color: AppColors.textSecondary),
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
              width: 260,
              padding: const EdgeInsets.all(14),
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
                boxShadow: [if (lit) const BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 8))],
              ),
              child: Row(
                children: [
                  LogoTile(channel: widget.channel, size: 64),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.2),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              lit ? Icons.play_circle_fill_rounded : Icons.play_circle_outline_rounded,
                              size: 18,
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

/// Großes Senderlogo zum direkten Anklicken.
class _LogoTileButton extends StatefulWidget {
  const _LogoTileButton({required this.channel, required this.onTap});

  final Channel channel;
  final VoidCallback onTap;

  @override
  State<_LogoTileButton> createState() => _LogoTileButtonState();
}

class _LogoTileButtonState extends State<_LogoTileButton> {
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
            scale: lit ? 1.05 : 1,
            duration: const Duration(milliseconds: 160),
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
                        color: _focused ? Colors.white : Colors.white.withValues(alpha: lit ? 0.2 : 0.08),
                        width: _focused ? 2 : 1,
                      ),
                      boxShadow: [
                        if (lit) const BoxShadow(color: Color(0x88000000), blurRadius: 16, offset: Offset(0, 8)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: MediaImage(
                        url: widget.channel.logo,
                        fit: BoxFit.contain,
                        padding: const EdgeInsets.all(18),
                        placeholder: Monogram(name: name.title, size: 72),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: lit ? AppColors.textPrimary : AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.keyboard_rounded, size: 16, color: AppColors.textSecondary),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Tipp: Mit ↑ ↓ wechselst du im Player den Sender, F öffnet das Vollbild, Leertaste pausiert.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
