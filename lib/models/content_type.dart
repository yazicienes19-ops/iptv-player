/// Die drei Inhaltsarten, die ein IPTV-Anbieter liefert.
enum ContentType {
  live('Live TV'),
  movie('Filme'),
  series('Serien');

  const ContentType(this.label);

  final String label;

  static ContentType fromName(String? name) =>
      ContentType.values.firstWhere((t) => t.name == name, orElse: () => ContentType.live);
}
