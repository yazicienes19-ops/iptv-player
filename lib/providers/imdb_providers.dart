import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/imdb_catalog.dart';
import '../services/imdb_catalog_store.dart';

final imdbCatalogStoreProvider = Provider((ref) => const ImdbCatalogStore());

class ImdbCatalogNotifier extends AsyncNotifier<ImdbCatalog?> {
  @override
  Future<ImdbCatalog?> build() => ref.watch(imdbCatalogStoreProvider).load();

  Future<void> importFile(String path) async {
    // Ungültige Importe ersetzen keinen bereits verwendbaren Katalog.
    final catalog = await ref.read(imdbCatalogStoreProvider).importFile(path);
    state = AsyncData(catalog);
  }

  Future<void> clear() async {
    await ref.read(imdbCatalogStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final imdbCatalogProvider = AsyncNotifierProvider<ImdbCatalogNotifier, ImdbCatalog?>(ImdbCatalogNotifier.new);

class ImdbFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? genre) => state = genre;
}

/// null = normale Mediathek; leerer String = alle IMDb-Genres.
final imdbFilterProvider = NotifierProvider<ImdbFilterNotifier, String?>(ImdbFilterNotifier.new);
