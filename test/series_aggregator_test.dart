import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/channel_name.dart';
import 'package:iptv_player/models/content_type.dart';
import 'package:iptv_player/services/series_aggregator.dart';

Channel ep(String name, [String category = 'c1']) => Channel(
  id: name,
  name: name,
  streamUrl: 'http://x/${name.hashCode}.mkv',
  type: ContentType.series,
  categoryId: category,
);

void main() {
  test('Folgen werden zu einer Serie mit Staffeln zusammengefasst', () {
    final result = SeriesAggregator.aggregate([
      ep('(DE-) 4 Blocks S01 E01'),
      ep('(DE-) 4 Blocks S01 E02'),
      ep('(DE-) 4 Blocks S02 E01'),
      ep('(DE-) Dark S01E01 - Geheimnisse'),
      ep('(DE-) 4 Blocks S03 E05'),
      ep('(EN-) 4 Blocks S01 E01'),
    ]);

    expect(result.series.map((s) => s.display.title), ['4 Blocks', 'Dark', '4 Blocks']);
    expect(result.series.first.display.country, 'DE');
    expect(result.series.last.display.country, 'EN');
    expect(result.series.every((s) => !s.isPlayable), isTrue);

    final blocks = result.seasons[result.series.first.id]!;
    expect(blocks.map((s) => s.number), [1, 2, 3]);
    expect(blocks.first.episodes.map((e) => e.number), [1, 2]);
    expect(blocks.last.episodes.single.number, 5);

    final dark = result.seasons[result.series[1].id]!;
    expect(dark.single.episodes.single.channel.name, 'Geheimnisse');
  });

  test('Andere Schreibweisen und Einträge ohne Muster', () {
    expect(SeriesAggregator.match('Haus des Geldes Staffel 2 Folge 7')?.season, 2);
    expect(SeriesAggregator.match('Friends 3x14')?.episode, 14);
    expect(SeriesAggregator.match('Breaking Bad Season 5 Episode 16')?.episode, 16);
    expect(SeriesAggregator.match('Tatort'), isNull);

    final result = SeriesAggregator.aggregate([ep('Tatort'), ep('Friends 1x01')]);
    expect(result.series.map((s) => s.display.title), ['Friends', 'Tatort']);
    expect(result.series.last.isPlayable, isTrue);
  });

  test('Performance: 69.000 Folgen in unter 2 Sekunden', () {
    final entries = [
      for (var show = 0; show < 3000; show++)
        for (var e = 1; e <= 23; e++) ep('(DE-) Serie $show S0${e % 3 + 1} E$e'),
    ];
    final watch = Stopwatch()..start();
    final result = SeriesAggregator.aggregate(entries);
    expect(result.series.length, 3000);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
