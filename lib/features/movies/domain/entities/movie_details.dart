import 'package:flutter/foundation.dart';

import 'cast_member.dart';
import 'movie.dart';

/// Full movie detail shown on the detail screen.
@immutable
class MovieDetails {
  const MovieDetails({
    required this.movie,
    this.tagline,
    this.runtime,
    this.voteCount = 0,
    this.genres = const <String>[],
    this.cast = const <CastMember>[],
  });

  final Movie movie;
  final String? tagline;
  final int? runtime;
  final int voteCount;
  final List<String> genres;
  final List<CastMember> cast;
}
