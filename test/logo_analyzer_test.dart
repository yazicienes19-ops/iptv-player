import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/logo_image.dart';

/// Bild aus [count] Pixeln einer Farbe plus durchsichtigem Rest.
List<int> image({required int total, required int count, required List<int> rgb}) => [
  for (var i = 0; i < total; i++) ...(i < count ? [...rgb, 255] : [0, 0, 0, 0]),
];

void main() {
  test('Dunkles Logo auf durchsichtigem Grund braucht eine helle Kachel', () {
    expect(LogoAnalyzer.classify(image(total: 100, count: 30, rgb: [20, 30, 60]), 100), LogoTone.dark);
    expect(LogoAnalyzer.classify(image(total: 100, count: 30, rgb: [0, 0, 0]), 100), LogoTone.dark);
  });

  test('Helles oder farbiges Logo bleibt auf der dunklen Kachel', () {
    expect(LogoAnalyzer.classify(image(total: 100, count: 30, rgb: [230, 40, 40]), 100), LogoTone.normal);
    expect(LogoAnalyzer.classify(image(total: 100, count: 30, rgb: [255, 255, 255]), 100), LogoTone.normal);
    // Kräftiges Dunkelblau (z. B. ein Senderlogo in Royalblau) ist noch sichtbar.
    expect(LogoAnalyzer.classify(image(total: 100, count: 30, rgb: [20, 60, 200]), 100), LogoTone.normal);
  });

  test('Logo mit eigenem deckendem Hintergrund bleibt normal, auch wenn dunkel', () {
    expect(LogoAnalyzer.classify(image(total: 100, count: 100, rgb: [10, 10, 10]), 100), LogoTone.normal);
  });

  test('Leeres oder fast unsichtbares Bild wird zum Monogramm', () {
    expect(LogoAnalyzer.classify(image(total: 100, count: 0, rgb: [0, 0, 0]), 100), LogoTone.empty);
    expect(LogoAnalyzer.classify(image(total: 1000, count: 5, rgb: [255, 255, 255]), 1000), LogoTone.empty);
  });
}
