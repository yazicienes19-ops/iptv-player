import 'channel_name.dart';
import 'content_type.dart';

class Category {
  const Category({required this.id, required this.name, required this.type, this.language});

  /// Aus einem Roh-Namen wie `(S|DE) Deutsche Serien`: bereinigter Name + Sprache.
  factory Category.cleaned({required String id, required String rawName, required ContentType type}) {
    final title = CategoryTitle.parse(rawName);
    return Category(id: id, name: title.name, type: type, language: title.language?.code);
  }

  factory Category.fromXtream(Map<String, dynamic> json, ContentType type) => Category.cleaned(
    id: '${json['category_id']}',
    rawName: (json['category_name'] as String?)?.trim() ?? 'Ohne Namen',
    type: type,
  );

  final String id;

  /// Bereinigter Anzeigename ohne Anbieter-Kürzel.
  final String name;
  final ContentType type;

  /// Sprachcode aus [Language], z. B. `de`; `null` wenn nicht erkennbar.
  final String? language;

  @override
  bool operator ==(Object other) => other is Category && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);
}
