import 'package:flutter/foundation.dart';

/// A subtitle track the user can toggle in the player.
@immutable
class SubtitleTrack {
  const SubtitleTrack({required this.label, required this.url});

  final String label;
  final String url;
}

/// A stream candidate produced by a source extractor.
///
/// [videoUrl] is the direct `.m3u8`/`.mp4` link that plays natively.
/// [embedUrl] is the source embed page (used as fallback if allowed).
@immutable
class VideoSource {
  const VideoSource({
    required this.sourceId,
    required this.label,
    this.videoUrl,
    this.embedUrl,
    this.quality = 'Auto',
    this.subtitles = const <SubtitleTrack>[],
    this.httpHeaders = const <String, String>{},
  });

  final String sourceId; // e.g. 'vidsrc_to'
  final String label; // human-readable provider name
  final String? videoUrl; // direct stream URL
  final String? embedUrl; // fallback embed page
  final String quality;
  final List<SubtitleTrack> subtitles;

  /// Extra HTTP headers mpv must send to the stream CDN, e.g. the exact
  /// `Referer` a provider API returns for its streams (VidNest). These
  /// override the player's derived headers (User-Agent / Referer from the
  /// embed URL) so a CDN that checks an exact Referer (verified 2026-08:
  /// goodstream.cc returns 403 without it, 200 with it) plays natively.
  final Map<String, String> httpHeaders;

  bool get isPlayable => videoUrl != null && videoUrl!.isNotEmpty;

  /// Returns a copy with any of the fields replaced.
  VideoSource copyWith({
    String? sourceId,
    String? label,
    String? videoUrl,
    String? embedUrl,
    String? quality,
    List<SubtitleTrack>? subtitles,
    Map<String, String>? httpHeaders,
  }) {
    return VideoSource(
      sourceId: sourceId ?? this.sourceId,
      label: label ?? this.label,
      videoUrl: videoUrl ?? this.videoUrl,
      embedUrl: embedUrl ?? this.embedUrl,
      quality: quality ?? this.quality,
      subtitles: subtitles ?? this.subtitles,
      httpHeaders: httpHeaders ?? this.httpHeaders,
    );
  }
}
