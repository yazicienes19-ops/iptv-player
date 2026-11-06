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
///
/// Mit [collapsible] ist sie nur eine schmale Symbolleiste und klappt auf, solange die
/// Maus darüber ist oder die Fernbedienung darin steht. Aufgeklappt legt sie sich über
/// den Inhalt, der dadurch nicht springt.
class GlassSidebar extends ConsumerStatefulWidget {
  const GlassSidebar({super.key, this.collapsible = false});

  static const width = 232.0;
  static const collapsedWidth = 72.0;

  final bool collapsible;

  @override
  ConsumerState<GlassSidebar> createState() => _GlassSidebarState();
}

class _GlassSidebarState extends ConsumerState<GlassSidebar> {
  bool _hovered = false;
  bool _focusInside = false;

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.collapsible && !_hovered && !_focusInside;
    const width = GlassSidebar.width;
    final panel = _panel(context, collapsed);
    if (!widget.collapsible) return panel;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onFocusChange: (inside) => setState(() => _focusInside = inside),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: collapsed ? GlassSidebar.collapsedWidth : width,
          decoration: BoxDecoration(
            border: const Border(right: BorderSide(color: Color(0x10FFFFFF))),
            boxShadow: [if (!collapsed) const BoxShadow(color: Color(0x99000000), blurRadius: 40)],
          ),
          child: ClipRect(
            child: OverflowBox(alignment: Alignment.centerLeft, minWidth: width, maxWidth: width, child: panel),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, bool collapsed) {
    final section = ref.watch(sectionProvider);
    const width = GlassSidebar.width;

    return SizedBox(
      width: width,
      child: Glass(
        border: false,
        tint: const Color(0xEB0B0E14),
        blur: 20,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0x10FFFFFF))),
          ),
          child: SafeArea(
            right: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactHeight = constraints.maxHeight < 640;
                final navItems = [
                  for (final s in AppSection.values)
                    _NavItem(
                      icon: s == section ? sectionIcons[s]!.$2 : sectionIcons[s]!.$1,
                      label: s.label,
                      selected: s == section,
                      compact: compactHeight,
                      collapsed: collapsed,
                      onTap: () => ref.read(sectionProvider.notifier).select(s),
                    ),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        collapsed ? 19 : 22,
                        compactHeight ? 8 : 26,
                        18,
                        compactHeight ? 12 : 28,
                      ),
                      child: _Brand(collapsed: collapsed),
                    ),
                    // Eingeklappt unsichtbar, behält aber seinen Platz: Die Symbole springen beim Aufklappen nicht.
                    IgnorePointer(
                      ignoring: collapsed,
                      child: AnimatedOpacity(
                        opacity: collapsed ? 0 : 1,
                        duration: const Duration(milliseconds: 150),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(14, 0, 14, compactHeight ? 8 : 22),
                          child: const LanguageFilterButton(),
                        ),
                      ),
                    ),
                    if (!compactHeight)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 16, 10),
                        child: Text(
                          collapsed ? '' : 'ENTDECKEN',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.8,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    if (section == AppSection.live) ...[
                      ...navItems,
                      const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 8), child: Divider(height: 1)),
                      const Expanded(
                        child: CategoryList(key: ValueKey(ContentType.live), type: ContentType.live),
                      ),
                    ] else
                      // In sehr niedrigen Fenstern lässt sich die Navigation scrollen statt abzuschneiden.
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: navItems),
                        ),
                      ),
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: collapsed ? GlassSidebar.width - GlassSidebar.collapsedWidth + 16 : 16,
                    ),
                    const SizedBox(height: 6),
                    _NavItem(
                      icon: Icons.playlist_play_rounded,
                      label: ref.watch(activePlaylistProvider)?.name ?? 'Playlist',
                      selected: false,
                      dense: true,
                      collapsed: collapsed,
                      onTap: () => showPlaylistSheet(context),
                    ),
                    _NavItem(
                      icon: Icons.settings_rounded,
                      label: 'Einstellungen',
                      selected: false,
                      dense: true,
                      collapsed: collapsed,
                      onTap: () => Navigator.of(context).push(SettingsPage.route()),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 6, 16, 14),
                      child: _VpnLine(collapsed: collapsed),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.collapsed = false});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.play_arrow_rounded, size: 25, color: AppColors.background),
        ),
        const SizedBox(width: 11),
        if (!collapsed)
          const Text('IpFlix', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
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
    this.compact = false,
    this.collapsed = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dense;
  final bool compact;

  /// Nur das Symbol, mittig in der schmalen Leiste; der Name steht im Tooltip.
  final bool collapsed;

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
    // Die Spalte streckt ihre Kinder; eingeklappt muss der Eintrag seine 48 px behalten.
    final item = widget.collapsed
        ? Align(alignment: Alignment.centerLeft, child: _item(lit, selected))
        : _item(lit, selected);
    return widget.collapsed
        ? Tooltip(message: widget.label, waitDuration: const Duration(milliseconds: 400), child: item)
        : item;
  }

  Widget _item(bool lit, bool selected) {
    final collapsed = widget.collapsed;
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
            // Eingeklappt 48 px breit und in der 72-px-Leiste mittig (12 + 48 + 12).
            width: collapsed ? 48 : null,
            margin: EdgeInsets.only(left: collapsed ? 12 : 14, right: collapsed ? 0 : 14, top: 3, bottom: 3),
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 12,
              vertical: widget.dense ? 9 : (widget.compact ? 10 : 12),
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.11)
                  : lit
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focused
                    ? Colors.white
                    : selected
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  widget.icon,
                  size: widget.dense ? 19 : 21,
                  color: selected ? AppColors.accent : (lit ? AppColors.textPrimary : AppColors.textSecondary),
                ),
                if (!collapsed) ...[
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
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
                    ),
                ],
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
  const _VpnLine({this.collapsed = false});

  final bool collapsed;

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
              collapsed
                  ? ''
                  : active
                  ? 'VPN geschützt'
                  : (blocked ? 'Blockiert (kein VPN)' : 'Direkte Verbindung'),
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
