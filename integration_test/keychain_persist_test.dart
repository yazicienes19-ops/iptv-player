// Prüft, ob Schlüsselbund-Einträge einen Neustart überleben.
// Lauf 1: --dart-define=PHASE=write, Lauf 2 (neuer Prozess): --dart-define=PHASE=read.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv_player/services/secure_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('PHASE');

  testWidgets('Schlüsselbund über Neustart ($phase)', (tester) async {
    final store = SecureStore();
    if (phase == 'write') {
      await store.write('persist.check', 'hallo');
    } else {
      final value = await store.read('persist.check');
      // ignore: avoid_print
      print('KEYCHAIN | gelesen nach Neustart: $value');
      await store.delete('persist.check');
      expect(value, 'hallo');
    }
  });
}
