/// A learner's named, ordered collection of library videos.
///
/// Videos are held by id (a YouTube item's id is its video id), so renaming or
/// re-fetching a video never touches the playlists it is in.
class Playlist {
  /// The two playlists every learner has. Favorites is saved like any other
  /// playlist; Recents is worked out from what was watched, never saved.
  static const favoritesId = 'favorites';
  static const recentsId = 'recents';

  /// How many videos Recents holds.
  static const recentsLimit = 20;

  final String id;
  final String name;
  final List<String> videoIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Playlist({
    required this.id,
    required this.name,
    this.videoIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isRecents => id == recentsId;
  bool get isFavorites => id == favoritesId;

  /// Built in: cannot be renamed or deleted.
  bool get isBuiltIn => isRecents || isFavorites;

  /// Recents fills itself, so its videos cannot be added, removed or moved.
  bool get isEditable => !isRecents;

  Playlist copyWith({
    String? name,
    List<String>? videoIds,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      videoIds: videoIds ?? this.videoIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'videoIds': videoIds,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Null for a document that is not a usable playlist.
  static Playlist? fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final name = map['name'];
    final createdAt = DateTime.tryParse('${map['createdAt']}');
    if (id is! String || name is! String || createdAt == null) return null;
    return Playlist(
      id: id,
      name: name,
      videoIds: [
        for (final videoId in (map['videoIds'] as List?) ?? const [])
          if (videoId is String) videoId,
      ],
      createdAt: createdAt,
      updatedAt: DateTime.tryParse('${map['updatedAt']}') ?? createdAt,
    );
  }
}
