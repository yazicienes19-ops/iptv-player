import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/playlist_credentials.dart';
import 'package:iptv_player/services/local_store.dart';

void main() {
  test('Xtream: Server, Benutzer und Passwort verschwinden aus Stream-URLs', () {
    const playlist = PlaylistCredentials(
      id: 'x',
      name: 'Anbieter',
      kind: PlaylistKind.xtream,
      serverUrl: 'http://panel.example.com:8080/',
      username: 'max123',
      password: 'geheim!pw',
    );
    final redactor = UrlRedactor.forPlaylist(playlist);
    const url = 'http://panel.example.com:8080/live/max123/geheim%21pw/4711.ts';

    final stored = redactor.redact(url);
    expect(stored, isNot(contains('max123')));
    expect(stored, isNot(contains('geheim')));
    expect(stored, isNot(contains('panel.example.com')));
    expect(redactor.restore(stored), url);

    // So baut XtreamApi die URL (Uri.encodeComponent lässt „!“ roh).
    const raw = 'http://panel.example.com:8080/live/max123/geheim!pw/4711.ts';
    expect(redactor.redact(raw), isNot(contains('geheim')));
    expect(redactor.restore(redactor.redact(raw)), raw);
  });

  test('M3U: Zugangsdaten aus der Playlist-URL werden ebenfalls geschwärzt', () {
    const playlist = PlaylistCredentials(
      id: 'm',
      name: 'M3U',
      kind: PlaylistKind.m3uUrl,
      m3uUrl: 'http://tv.example.net/get.php?username=anna&password=s3cret&type=m3u_plus',
    );
    final redactor = UrlRedactor.forPlaylist(playlist);
    const url = 'http://tv.example.net/anna/s3cret/99.ts';

    final stored = redactor.redact(url);
    expect(stored, 'http://tv.example.net/{{user}}/{{pass}}/99.ts');
    expect(redactor.restore(stored), url);
  });

  test('Öffentliche URLs bleiben unverändert', () {
    const playlist = PlaylistCredentials(
      id: 'p',
      name: 'Öffentlich',
      kind: PlaylistKind.m3uUrl,
      m3uUrl: 'https://iptv-org.github.io/iptv/countries/de.m3u',
    );
    const url = 'https://daserste-live.ard-mcdn.de/daserste/live/hls/int/master.m3u8';
    expect(UrlRedactor.forPlaylist(playlist).redact(url), url);
  });
}
