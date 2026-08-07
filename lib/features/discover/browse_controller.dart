import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/providers.dart';
import '../../data/tmdb/catalog_item.dart';
import '../../data/tmdb/tmdb_api.dart';

part 'browse_controller.g.dart';

@riverpod
Future<List<Genre>> catalogGenres(Ref ref, MediaKind kind) async {
  final tmdb = ref.watch(tmdbApiProvider);
  if (tmdb == null) return const [];
  return tmdb.genres(kind);
}

/// One Browse rail: first page only. A null [genreId] means this week's
/// trending entries.
@riverpod
Future<List<CatalogItem>> catalogRow(
  Ref ref, {
  required MediaKind kind,
  int? genreId,
}) async {
  final tmdb = ref.watch(tmdbApiProvider);
  if (tmdb == null) return const [];
  if (genreId == null) return tmdb.trending(kind);
  return tmdb.discover(kind, genreId: genreId);
}

/// Paginated, sortable category grid backing the infinite-scrolling screen.
@riverpod
class CategoryGrid extends _$CategoryGrid {
  int _page = 0;
  bool _end = false;

  @override
  Future<List<CatalogItem>> build({
    required MediaKind kind,
    required CatalogSort sort,
    int? genreId,
  }) async {
    return _fetch();
  }

  Future<List<CatalogItem>> _fetch() async {
    final tmdb = ref.read(tmdbApiProvider);
    if (tmdb == null) return const [];
    _page++;
    final items = await tmdb.discover(kind,
        sort: sort, genreId: genreId, page: _page);
    if (items.isEmpty) _end = true;
    return items;
  }

  Future<void> loadMore() async {
    if (_end || state.isLoading) return;
    final current = state.value ?? const [];
    final more = await _fetch();
    if (more.isNotEmpty) {
      // TMDB can repeat an entry across pages.
      final seen = current.map((e) => e.tmdbId).toSet();
      state = AsyncData([
        ...current,
        ...more.where((e) => seen.add(e.tmdbId)),
      ]);
    }
  }
}
