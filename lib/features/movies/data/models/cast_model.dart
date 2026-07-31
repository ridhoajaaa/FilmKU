import '../../domain/entities/cast_member.dart';

/// [CastMember] with TMDB JSON parsing.
class CastModel extends CastMember {
  const CastModel({
    required super.id,
    required super.name,
    required super.character,
    super.profilePath,
    super.order,
  });

  factory CastModel.fromJson(Map<String, dynamic> json) => CastModel(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        character: (json['character'] as String?) ?? '',
        profilePath: json['profile_path'] as String?,
        order: (json['order'] as num?)?.toInt() ?? 0,
      );
}
