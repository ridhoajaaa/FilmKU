import 'package:flutter/foundation.dart';

/// A cast member / actor shown on the detail screen.
@immutable
class CastMember {
  const CastMember({
    required this.id,
    required this.name,
    required this.character,
    this.profilePath,
    this.order = 0,
  });

  final int id;
  final String name;
  final String character;
  final String? profilePath;
  final int order;
}
