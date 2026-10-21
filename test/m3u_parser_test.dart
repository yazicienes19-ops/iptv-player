import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/services/m3u_parser.dart';

void main() {
  const sample = '''#EXTM3U
#EXTINF:-1 tvg-id="das.erste" tvg-logo="http://logo/ard.png" group-title="DE | Vollprogramm",Das Erste HD
http://example.com:8080/live/u/p/1.ts
#EXTINF:-1 tvg-name="ZDF" group-title="DE | Vollprogramm",ZDF, HD
http://example.com:8080/live/u/p/2.ts
#EXTINF:-1 group-title="VOD | Action",Ein Film (2024)
http://example.com:8080/movie/u/p/10.mkv
#EXTINF:-1 group-title="Serien | Drama",Serie S01E01
http://example.com:8080/series/u/p/20.mp4
#EXTINF:-1 group-title="Movies",Pluto TV Movies
https://pluto.example/live/movies/master.m3u8
#EXTINF:-1 group-title="VOD | Test",HLS Film
https://cdn.example/vod/film/master.m3u8
#EXTINF:-1,Ohne Gruppe
#EXTGRP:Sonstiges
http://example.com/stream.m3u8
''';

  test('trennt Live, Filme und Serien und liest Attribute', () {
    final result = M3uParser.parse(sample);

    final live = result[ContentType.live];
    expect(live.channels.map((c) => c.name), ['Das Erste HD', 'ZDF, HD', 'Pluto TV Movies', 'Ohne Gruppe']);
    expect(live.channels.first.logo, 'http://logo/ard.png');
    expect(live.channels.first.epgChannelId, 'das.erste');
    expect(live.categories.map((c) => c.name), ['Vollprogramm', 'Movies', 'Sonstiges']);
    expect(live.categories.first.language, 'de');

    expect(result[ContentType.movie].channels.map((c) => c.name), ['Ein Film (2024)', 'HLS Film']);
    final series = result[ContentType.series];
    expect(series.channels.single.name, 'Serie');
    final episode = series.seriesSeasons[series.channels.single.id]!.single.episodes.single;
    expect(episode.channel.streamUrl, endsWith('/series/u/p/20.mp4'));
  });

  test('IDs bleiben bei doppelten URLs eindeutig', () {
    const dup = '#EXTM3U\n#EXTINF:-1,A\nhttp://x/1.ts\n#EXTINF:-1,B\nhttp://x/1.ts\n';
    final ids = M3uParser.parse(dup)[ContentType.live].channels.map((c) => c.id).toSet();
    expect(ids.length, 2);
  });
}
