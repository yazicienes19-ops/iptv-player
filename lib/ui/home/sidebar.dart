import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/content_type.dart';
import '../../providers/app_providers.dart';
import '../playlists/playlist_sheet.dart';
import '../settings/settings_page.dart';
import '../theme.dart';
import '../widgets/category_views.dart';
import '../widgets/glass.dart';
import '../widgets/tv_focus.dart';
import '../widgets/vpn_badge.dart';
import 'home_shell.dart';

/// Schlanke Glas-Seitenleiste im Stil von Apple TV:
/// Sprachfilter, Hauptnavigation, unten Einstellungen und VPN-Punkt.
/// Nur bei Live TV erscheinen darunter die Kategorien.
class GlassSidebar extends ConsumerWidget {
  const GlassSidebar({super.key});

  static const width = 232.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sectionProvider);

    return SizedBox(
      width: width,
      child: Glass(
        border: false,
        tint: const Color(0xB80C0E13),
        blur: 32,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0x14FFFFFF))),
          ),
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(padding: EdgeInsets.fromLTRB(20, 18, 16, 14), child: _Brand()),
                const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 14), child: LanguageFilterButton()),
                for (final s in AppSection.values)
                  _NavItem(
                    icon: s == section ? sectionIcons[s]!.$2 : sectionIcons[s]!.$1,
                    label: s.label,
                    selected: s == section,
                    onTap: () => ref.read(sectionProvider.notifier).select(s),
                  ),
                if (section == AppSection.live) ...[
                  const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 8), child: Divider(height: 1)),
                  const Expanded(
                    child: CategoryList(key: ValueKey(ContentType.live), type: ContentType.live),
                  ),
                ] else
                  const Spacer(),
                const Divider(height: 1, indent: 16, endIndent: 16),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.playlist_play_rounded,
                  label: ref.watch(activePlaylistProvider)?.name ?? 'Playlist',
                  selected: false,
                  dense: true,
                  onTap: () => showPlaylistSheet(context),
                ),
                _NavItem(
                  icon: Icons.settings_rounded,
                  label: 'Einstellungen',
                  selected: false,
                  dense: true,
                  onTap: () => Navigator.of(context).push(SettingsPage.route()),
                ),
                const Padding(padding: EdgeInsets.fromLTRB(22, 6, 16, 14), child: _VpnLine()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
          child: const Icon(Icons.monitor_heart_outlined, size: 16, color: Colors.white),
        ),
        const SizedBox(width: 10),
        const Text('Pulse Media', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
      ],
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dense;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _focused;
    final selected = widget.selected;
    return TvFocus(
      onActivate: widget.onTap,
      onFocusChange: (v) => setState(() => _focused = v),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.dense ? 8 : 11),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.12)
                  : lit
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 2),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: widget.dense ? 19 : 21,
                  color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.dense ? 13 : 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected || lit ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (selected && !widget.dense)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Einzeiliger VPN-Hinweis mit farbigem Punkt.
class _VpnLine extends ConsumerWidget {
  const _VpnLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(vpnStatusProvider).value?.active ?? false;
    final blocked = ref.watch(networkBlockedProvider);
    final color = active ? vpnGreen : vpnYellow;
    return Tooltip(
      message: blocked ? 'Kill-Switch blockiert alle Verbindungen' : (active ? 'VPN aktiv' : 'Kein VPN erkannt'),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              active ? 'VPN geschützt' : (blocked ? 'Blockiert (kein VPN)' : 'Direkte Verbindung'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
