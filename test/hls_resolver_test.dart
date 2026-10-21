import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/hls_resolver.dart';

void main() {
  const ardMaster = '''#EXTM3U
#EXT-X-VERSION:4
#EXT-X-MEDIA:TYPE=AUDIO,LANGUAGE="de",NAME="Deutsch",AUTOSELECT=YES,DEFAULT=YES,CHANNELS="2",GROUP-ID="program_audio",URI="masteraudio1.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,LANGUAGE="de",NAME="Klare Sprache",AUTOSELECT=YES,DEFAULT=NO,CHANNELS="2",GROUP-ID="program_audio",URI="masteraudio2.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,NAME="Deutsch",DEFAULT=YES,GROUP-ID="subs",URI="mastersubs.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=2147200,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=640x360,AUDIO="program_audio",SUBTITLES="subs"
master360p1200.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=8500800,CODECS="avc1.64002a,mp4a.40.2",RESOLUTION=1920x1080,AUDIO="program_audio",SUBTITLES="subs"
master1080p5000.m3u8
''';

  test('wählt die beste Variante und sammelt die Tonspuren', () {
    final r = HlsResolver.parseMaster(ardMaster, 'https://cdn.example/live/hls/master.m3u8')!;
    expect(r.url, 'https://cdn.example/live/hls/master1080p5000.m3u8');
    expect(r.audio.map((a) => a.name), ['Deutsch', 'Klare Sprache']);
    expect(r.audio.first.url, 'https://cdn.example/live/hls/masteraudio1.m3u8');
    expect(r.audio.first.language, 'de');
  });

  test('normale Master-Playlist bleibt unverändert', () {
    const plain = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1672000\nmaster-360p.m3u8\n';
    expect(HlsResolver.parseMaster(plain, 'https://x/master.m3u8'), isNull);
  });

  test('nur .m3u8 wird aufgelöst', () {
    expect(HlsResolver.looksLikeHls('http://x/live/u/p/1.ts'), isFalse);
    expect(HlsResolver.looksLikeHls('https://x/a/master.m3u8?token=1'), isTrue);
  });
}
