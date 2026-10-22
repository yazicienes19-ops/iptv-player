/// Sprachen bzw. Länder für den Schnellfilter. IPTV-Anbieter kennzeichnen
/// Inhalte mit Länderkürzeln (`DE`, `UK`, `TR` …); mehrere Kürzel können
/// zur selben Sprache gehören.
class Language {
  const Language(this.code, this.label, this.flag, this.aliases, [this.words = const {}]);

  final String code;
  final String label;
  final String flag;
  final Set<String> aliases;

  /// Länder-, Sprach- und eindeutige Markennamen in Kategorien („✪ SWITZERLAND“, „MAGENTA TV“).
  final Set<String> words;

  static const all = <Language>[
    Language(
      'de',
      'Deutsch',
      '🇩🇪',
      {'DE', 'GER', 'DEU', 'AT', 'AUT', 'CH', 'GERMANY', 'DEUTSCH'},
      {
        'germany',
        'deutschland',
        'german',
        'deutsch',
        'deutsche',
        'austria',
        'österreich',
        'osterreich',
        'switzerland',
        'schweiz',
        'swiss',
        'magenta',
        'teleclub',
        'blue sport',
        'sky de',
        'waipu',
        'zattoo',
      },
    ),
    Language(
      'en',
      'English',
      '🇬🇧',
      {'EN', 'ENG', 'UK', 'GB', 'US', 'USA', 'CA', 'AU', 'IE', 'ENGLISH'},
      {
        'united kingdom',
        'england',
        'scotland',
        'ireland',
        'usa',
        'united states',
        'america',
        'canada',
        'australia',
        'new zealand',
        'english',
      },
    ),
    Language(
      'tr',
      'Türkçe',
      '🇹🇷',
      {'TR', 'TUR', 'TURK', 'TÜRK', 'TURKEY'},
      {'turkey', 'türkiye', 'turkiye', 'turkish', 'türk', 'turk', 'türkçe', 'turkce', 'ulusal', 'yerli'},
    ),
    Language(
      'sq',
      'Shqip',
      '🇦🇱',
      {'AL', 'ALB', 'ALBANIA', 'KS', 'XK', 'KOSOVO'},
      {'albania', 'shqip', 'shqiperi', 'kosovo', 'kosova'},
    ),
    Language(
      'ar',
      'العربية',
      '🇸🇦',
      {'AR', 'ARA', 'ARAB', 'ARABIC', 'SA', 'AE', 'EG', 'MA'},
      {'arabic', 'arab', 'arabia'},
    ),
    Language('el', 'Ελληνικά', '🇬🇷', {'GR', 'GRE', 'GREECE', 'EL'}, {'greece', 'greek', 'ellada', 'hellas'}),
    Language('fr', 'Français', '🇫🇷', {'FR', 'FRA', 'FRANCE', 'BE'}, {'france', 'french', 'français', 'francais'}),
    Language('it', 'Italiano', '🇮🇹', {'IT', 'ITA', 'ITALY'}, {'italy', 'italia', 'italian'}),
    Language(
      'es',
      'Español',
      '🇪🇸',
      {'ES', 'ESP', 'SPAIN', 'LAT', 'MX'},
      {'spain', 'españa', 'espana', 'spanish', 'latino', 'mexico'},
    ),
    Language(
      'nl',
      'Nederlands',
      '🇳🇱',
      {'NL', 'NLD', 'NETHERLANDS'},
      {'netherlands', 'nederland', 'holland', 'dutch'},
    ),
    Language('pl', 'Polski', '🇵🇱', {'PL', 'POL', 'POLAND'}, {'poland', 'polska', 'polish'}),
    Language('ru', 'Русский', '🇷🇺', {'RU', 'RUS', 'RUSSIA'}, {'russia', 'russian'}),
    Language('pt', 'Português', '🇵🇹', {'PT', 'POR', 'BR', 'BRA'}, {'portugal', 'brazil', 'brasil', 'portuguese'}),
    Language(
      'exyu',
      'Ex-YU',
      '🇷🇸',
      {'EXYU', 'EX-YU', 'YU', 'RS', 'HR', 'BA', 'BIH', 'SRB', 'HRV', 'SI', 'MK', 'ME'},
      {'ex-yu', 'exyu', 'serbia', 'croatia', 'bosnia', 'slovenia', 'macedonia', 'montenegro', 'balkan'},
    ),
    Language('ku', 'Kurdî', '☀️', {'KU', 'KURD', 'KURDISH'}, {'kurdish', 'kurdi', 'kurd'}),
    Language('fa', 'فارسی', '🇮🇷', {'IR', 'FA', 'PERSIAN', 'FARSI'}, {'iran', 'persian', 'farsi'}),
    Language('in', 'India', '🇮🇳', {'IN', 'IND', 'INDIA', 'HINDI'}, {'india', 'hindi', 'indian'}),
  ];

  static final _byAlias = {
    for (final language in all)
      for (final alias in language.aliases) alias: language,
  };

  static final _wordPatterns = [
    for (final language in all)
      for (final word in language.words)
        (RegExp('(?:^|[^a-zäöüçğışé])${RegExp.escape(word)}(?:\$|[^a-zäöüçğışé])'), language),
  ];

  /// Erkennt eine Sprache an Länder-/Markennamen im Text, z. B. „✪ SWITZERLAND“.
  /// Längere Treffer gewinnen („new zealand“ vor „zealand“).
  static Language? fromText(String text) {
    final lower = text.toLowerCase();
    Language? best;
    var bestLength = 0;
    for (final (pattern, language) in _wordPatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null && match.group(0)!.length > bestLength) {
        best = language;
        bestLength = match.group(0)!.length;
      }
    }
    return best;
  }

  /// `null` für unbekannte Kürzel wie `VIP`, `4K` oder `TOP`.
  static Language? fromCode(String? code) => code == null ? null : _byAlias[code.toUpperCase()];

  static Language? byCode(String? code) {
    for (final language in all) {
      if (language.code == code) return language;
    }
    return null;
  }
}
