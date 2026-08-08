import 'package:dio/dio.dart';

/// TheTVDB v4 client (https://thetvdb.github.io/v4-api/), the primary source of
/// show metadata: it lists new seasons before the other providers do, and
/// serves translated episode titles and overviews.
///
/// Show ids in this app are already TheTVDB ids (that is what the TV Time
/// export contains), so no id resolution is needed.
class TvdbApi {
  /// Leaving [apiKey] empty expects [dio] to reach a proxy that authenticates
  /// upstream on its behalf; the login round trip is then skipped.
  TvdbApi({this.apiKey = '', this.language = 'eng', Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api4.thetvdb.com/v4',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );

  final String apiKey;
  final Dio _dio;

  /// ISO 639-2/T code used for translation endpoints.
  final String language;

  String? _token;

  static const _artworks = 'https://artworks.thetvdb.com';

  /// `POST /login` returns a token valid for about a month; caching it for the
  /// session avoids one round trip per request.
  Future<void> _ensureAuth() async {
    if (apiKey.isEmpty || _token != null) return;
    final r = await _dio.post<Map<String, dynamic>>(
      '/login',
      data: {'apikey': apiKey},
    );
    _token = (r.data?['data'] as Map<String, dynamic>?)?['token'] as String?;
  }

  Options get _auth => _token == null
      ? Options()
      : Options(headers: {'Authorization': 'Bearer $_token'});

  static String? _img(String? p) {
    if (p == null || p.isEmpty) return null;
    return p.startsWith('http') ? p : '$_artworks$p';
  }

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  /// Show metadata plus every episode. Null when TheTVDB does not know the id.
  Future<TvdbSeries?> series(int tvdbId) async {
    await _ensureAuth();
    Response<Map<String, dynamic>> ext;
    try {
      ext = await _dio.get<Map<String, dynamic>>(
        '/series/$tvdbId/extended',
        options: _auth,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
    final d = ext.data?['data'] as Map<String, dynamic>? ?? const {};

    String? localName, localOverview;
    try {
      final t = await _dio.get<Map<String, dynamic>>(
        '/series/$tvdbId/translations/$language',
        options: _auth,
      );
      final td = t.data?['data'] as Map<String, dynamic>?;
      localName = _nonEmpty(td?['name'] as String?);
      localOverview = _nonEmpty(td?['overview'] as String?);
    } catch (_) {
      // No translation available: fall back to the original text below.
    }

    final status = (d['status'] as Map<String, dynamic>?)?['name'] as String?;
    final network =
        (d['latestNetwork'] as Map<String, dynamic>?)?['name'] as String?;

    return TvdbSeries(
      name: localName ?? (d['name'] as String? ?? ''),
      overview: localOverview,
      poster: _img(d['image'] as String?),
      status: status,
      network: network,
      episodes: await _episodes(tvdbId),
    );
  }

  /// Specials (season 0) are returned here; the merge step is what drops them
  /// from progress tracking.
  Future<List<TvdbEpisode>> _episodes(int tvdbId) async {
    final out = <TvdbEpisode>[];
    var page = 0;
    while (true) {
      final r = await _dio.get<Map<String, dynamic>>(
        '/series/$tvdbId/episodes/official/$language',
        queryParameters: {'page': page},
        options: _auth,
      );
      final data = r.data?['data'] as Map<String, dynamic>? ?? const {};
      final eps = data['episodes'] as List? ?? const [];
      for (final e in eps.cast<Map<String, dynamic>>()) {
        // This endpoint returns ids and numbers as strings.
        final season = int.tryParse('${e['seasonNumber']}') ?? 0;
        final number = int.tryParse('${e['number']}') ?? 0;
        final aired = e['aired'] as String?;
        out.add(
          TvdbEpisode(
            season: season,
            number: number,
            name: (e['name'] as String?) ?? '',
            overview: _nonEmpty(e['overview'] as String?),
            still: _img(e['image'] as String?),
            // Anchored at noon UTC so the date does not shift a day either way
            // when rendered in the device timezone.
            airDate: (aired == null || aired.isEmpty)
                ? null
                : DateTime.tryParse('${aired}T12:00:00Z'),
          ),
        );
      }
      if ((r.data?['links'] as Map<String, dynamic>?)?['next'] == null) break;
      page++;
    }
    return out;
  }
}

class TvdbSeries {
  const TvdbSeries({
    required this.name,
    this.overview,
    this.poster,
    this.status,
    this.network,
    this.episodes = const [],
  });

  final String name;
  final String? overview;
  final String? poster;
  final String? status; // Continuing / Ended / Upcoming
  final String? network;
  final List<TvdbEpisode> episodes;
}

/// Optional fields stay null when absent so the merge never overwrites an
/// existing value with a blank one.
class TvdbEpisode {
  const TvdbEpisode({
    required this.season,
    required this.number,
    required this.name,
    this.overview,
    this.still,
    this.airDate,
  });

  final int season;
  final int number;
  final String name;
  final String? overview;
  final String? still;
  final DateTime? airDate;

  bool get isSpecial => season == 0;
}
