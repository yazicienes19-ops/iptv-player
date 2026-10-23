import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tmdb.dart';
import '../../providers/app_providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_image.dart';
import 'tmdb_widgets.dart';

const _months = ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', 'Aug.', 'Sept.', 'Okt.', 'Nov.', 'Dez.'];

String _date(DateTime d) => '${d.day}. ${_months[d.month - 1]} ${d.year}';

/// Schauspieler bzw. Regie: Foto, Steckbrief, Biografie und – vor allem –
/// was davon in der eigenen Playlist abspielbar ist.
class PersonPage extends ConsumerStatefulWidget {
  const PersonPage({super.key, required this.personId, required this.name});

  static Route<void> route(int id, String name) => MaterialPageRoute(
    builder: (_) => PersonPage(personId: id, name: name),
  );

  final int personId;
  final String name;

  @override
  ConsumerState<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends ConsumerState<PersonPage> {
  bool _bioExpanded = false;

  @override
  Widget build(BuildContext context) {
    final person = ref.watch(tmdbPersonProvider(widget.personId));
    return Scaffold(
      appBar: AppBar(title: Text(widget.name), backgroundColor: AppColors.background),
      body: person.when(
        loading: () => const AsyncStateView.loading(),
        error: (e, _) =>
            AsyncStateView.error(error: e, onRetry: () => ref.invalidate(tmdbPersonProvider(widget.personId))),
        data: (p) => LayoutBuilder(builder: (context, c) => _content(context, p, compact: c.maxWidth < 760)),
      ),
    );
  }

  Widget _content(BuildContext context, TmdbPerson person, {required bool compact}) {
    final index = ref.watch(playlistTitleIndexProvider);
    final available = person.credits.where((c) => index.find(c) != null).toList();
    final others = person.credits.where((c) => index.find(c) == null && c.posterPath != null).take(24).toList();
    final hPad = compact ? 16.0 : 40.0;
    final textTheme = Theme.of(context).textTheme;

    final facts = [
      ?person.knownFor,
      if (person.birthday != null)
        person.deathday == null
            ? '${person.age} Jahre (geb. ${_date(person.birthday!)})'
            : '${_date(person.birthday!)} – ${_date(person.deathday!)}',
      ?person.placeOfBirth,
    ];

    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: compact ? 150 : 240,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: MediaImage(
            url: person.photo,
            placeholder: const ColoredBox(color: AppColors.surfaceHigh),
          ),
        ),
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          person.name,
          style: (compact ? textTheme.headlineMedium : textTheme.displaySmall)?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(facts.join('  ·  '), style: const TextStyle(color: AppColors.textSecondary)),
        ],
        if (person.biography != null) ...[
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              person.biography!,
              maxLines: _bioExpanded ? null : 6,
              overflow: _bioExpanded ? null : TextOverflow.fade,
              style: const TextStyle(height: 1.55, color: Color(0xFFD0D3D9)),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _bioExpanded = !_bioExpanded),
            child: Text(_bioExpanded ? 'Weniger anzeigen' : 'Mehr lesen'),
          ),
        ],
      ],
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(0, 16, 0, 40),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [photo, const SizedBox(height: 20), info],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    photo,
                    const SizedBox(width: 36),
                    Expanded(child: info),
                  ],
                ),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: TmdbSectionTitle(
            available.isEmpty ? 'Nichts davon in deiner Playlist' : 'In deiner Playlist · ${available.length}',
          ),
        ),
        const SizedBox(height: 10),
        if (available.isNotEmpty) TmdbRow(items: available, horizontalPadding: hPad),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 24),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: const TmdbSectionTitle('Bekannt aus'),
          ),
          const SizedBox(height: 10),
          TmdbRow(items: others, horizontalPadding: hPad, width: 130),
        ],
      ],
    );
  }
}
