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
}
