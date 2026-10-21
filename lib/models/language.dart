/// Sprachen bzw. Länder für den Schnellfilter. IPTV-Anbieter kennzeichnen
/// Inhalte mit Länderkürzeln (`DE`, `UK`, `TR` …); mehrere Kürzel können
/// zur selben Sprache gehören.
class Language {
  const Language(this.code, this.label, this.flag, this.aliases);

  final String code;
  final String label;
  final String flag;
  final Set<String> aliases;

  static const all = <Language>[
    Language('de', 'Deutsch', '🇩🇪', {'DE', 'GER', 'DEU', 'AT', 'CH', 'GERMANY', 'DEUTSCH'}),
    Language('en', 'English', '🇬🇧', {'EN', 'ENG', 'UK', 'GB', 'US', 'USA', 'CA', 'AU', 'IE', 'ENGLISH'}),
    Language('tr', 'Türkçe', '🇹🇷', {'TR', 'TUR', 'TURK', 'TÜRK', 'TURKEY'}),
    Language('sq', 'Shqip', '🇦🇱', {'AL', 'ALB', 'ALBANIA', 'KS', 'XK', 'KOSOVO'}),
    Language('ar', 'العربية', '🇸🇦', {'AR', 'ARA', 'ARAB', 'ARABIC', 'SA', 'AE', 'EG', 'MA'}),
    Language('fr', 'Français', '🇫🇷', {'FR', 'FRA', 'FRANCE', 'BE'}),
    Language('it', 'Italiano', '🇮🇹', {'IT', 'ITA', 'ITALY'}),
    Language('es', 'Español', '🇪🇸', {'ES', 'ESP', 'SPAIN', 'LAT', 'MX'}),
    Language('nl', 'Nederlands', '🇳🇱', {'NL', 'NLD', 'NETHERLANDS'}),
    Language('pl', 'Polski', '🇵🇱', {'PL', 'POL', 'POLAND'}),
    Language('ru', 'Русский', '🇷🇺', {'RU', 'RUS', 'RUSSIA'}),
    Language('pt', 'Português', '🇵🇹', {'PT', 'POR', 'BR', 'BRA'}),
    Language('exyu', 'Ex-YU', '🇷🇸', {'EXYU', 'EX-YU', 'YU', 'RS', 'HR', 'BA', 'BIH', 'SRB', 'HRV', 'SI', 'MK', 'ME'}),
    Language('ku', 'Kurdî', '☀️', {'KU', 'KURD', 'KURDISH'}),
    Language('fa', 'فارسی', '🇮🇷', {'IR', 'FA', 'PERSIAN', 'FARSI'}),
    Language('in', 'India', '🇮🇳', {'IN', 'IND', 'INDIA', 'HINDI'}),
  ];

  static final _byAlias = {
    for (final language in all)
      for (final alias in language.aliases) alias: language,
  };

  /// `null` für unbekannte Kürzel wie `VIP`, `4K` oder `TOP`.
  static Language? fromCode(String? code) => code == null ? null : _byAlias[code.toUpperCase()];

  static Language? byCode(String? code) {
    for (final language in all) {
      if (language.code == code) return language;
    }
    return null;
  }
}
