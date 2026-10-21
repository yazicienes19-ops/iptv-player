import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel_name.dart';

void main() {
  test('Länderpräfix und Qualität werden herausgelöst', () {
    final a = ChannelName.parse('AL: TOP CHANNEL HEVC');
    expect(a.title, 'TOP CHANNEL');
    expect(a.country, 'AL');
    expect(a.qualities, [QualityTag.hevc]);

    final b = ChannelName.parse('DE | DAS ERSTE FHD');
    expect(b.title, 'DAS ERSTE');
    expect(b.country, 'DE');
    expect(b.qualities, [QualityTag.fhd]);

    final c = ChannelName.parse('UK - BBC One 4K 50FPS');
    expect(c.title, 'BBC One');
    expect(c.country, 'UK');
    expect(c.qualities, [QualityTag.uhd, QualityTag.fps50]);
  });

  test('Auflösung in Klammern und Hinweise aus iptv-org-Listen', () {
    final n = ChannelName.parse('arte (Germany) (720p) [Geo-blocked]');
    expect(n.title, 'arte (Germany)');
    expect(n.qualities, [QualityTag.hd]);
    expect(n.notes, ['Geo-blocked']);

    expect(ChannelName.parse('Das Erste HD (1080p)').qualities, [QualityTag.fhd]);
    expect(ChannelName.parse('Das Erste HD (1080p)').title, 'Das Erste');
  });

  test('Trennzeilen werden erkannt', () {
    for (final raw in ['AL: ----- SPORT -----', '===== NEWS =====', '*** KIDS ***', '##### DE #####']) {
      expect(ChannelName.parse(raw).isSeparator, isTrue, reason: raw);
    }
    expect(ChannelName.parse('AL: ----- SPORT -----').title, 'SPORT');
    expect(ChannelName.parse('1-2-3.tv (270p)').isSeparator, isFalse);
  });

  test('Qualitätswort am Anfang bleibt Teil des Namens', () {
    expect(ChannelName.parse('HD Plus Info').title, 'HD Plus Info');
    expect(ChannelName.parse('ZDF').title, 'ZDF');
  });

  test('Anbieter-Präfixe und Jahreszahl bei Filmen und Serien', () {
    final a = ChannelName.parse('(DE-) K2: Das Letzte Abenteuer - 1991');
    expect(a.title, 'K2: Das Letzte Abenteuer');
    expect(a.year, 1991);
    expect(a.country, 'DE');

    final b = ChannelName.parse('(V|DE) Dune: Part Two (2024)');
    expect(b.title, 'Dune: Part Two');
    expect(b.year, 2024);

    expect(ChannelName.parse('(S|DE) 4 Blocks S01 E01').title, '4 Blocks S01 E01');
    expect(ChannelName.parse('Blade Runner 2049').year, isNull);
    expect(ChannelName.parse('1917').title, '1917');
  });

  test('Kategorien: Kürzel weg, Sprache erkannt, Jahres-Kategorien umbenannt', () {
    final a = CategoryTitle.parse('(S|DE) Deutsche Serien');
    expect(a.name, 'Deutsche Serien');
    expect(a.language?.code, 'de');

    expect(CategoryTitle.parse('(V|DE) Filme - 2026', currentYear: 2026).name, 'Neuerscheinungen 2026');
    expect(CategoryTitle.parse('(V|DE) Filme - 2019', currentYear: 2026).name, 'Filme 2019');
    expect(CategoryTitle.parse('|TR| Yerli Diziler').language?.code, 'tr');
    expect(CategoryTitle.parse('UK - Sports').language?.code, 'en');
    expect(CategoryTitle.parse('VIP | Action').language, isNull);
  });

  test('Kategorien mit Länderkürzel ohne Trennzeichen', () {
    final a = CategoryTitle.parse('AL SPORTS');
    expect(a.language?.code, 'sq');
    expect(a.name, 'SPORTS');
    expect(CategoryTitle.parse('AL').name, 'Shqip');
    expect(CategoryTitle.parse('DE SPORT').language?.code, 'de');
    expect(CategoryTitle.parse('TV Serien').language, isNull);
    expect(CategoryTitle.parse('TV Serien').name, 'TV Serien');
    expect(CategoryTitle.parse('HD Kanäle').language, isNull);
  });
}
