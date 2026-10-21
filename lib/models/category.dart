import 'content_type.dart';

class Category {
  const Category({required this.id, required this.name, required this.type});

  final String id;
  final String name;
  final ContentType type;

  factory Category.fromXtream(Map<String, dynamic> json, ContentType type) => Category(
        id: '${json['category_id']}',
        name: (json['category_name'] as String?)?.trim() ?? 'Ohne Namen',
        type: type,
      );

  @override
  bool operator ==(Object other) => other is Category && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);
}
