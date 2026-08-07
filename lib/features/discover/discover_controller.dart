import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/providers.dart';
import '../../data/tmdb/catalog_item.dart';
import '../../data/tmdb/tmdb_api.dart';
import 'library_add.dart';

part 'discover_controller.g.dart';

/// Card queue behind the swipe deck for one media kind, mixing trending and
/// popular entries and skipping anything already tracked or already swiped.
///
/// The queue deliberately does not rebuild on each swipe — the UI holds a
/// cursor instead, which keeps a card from flickering as it flies out.
@riverpod
class DiscoverDeck extends _$DiscoverDeck {
  int _page = 0;
  final _loadedIds = <int>{};
  final _excluded = <int>{}; // tracked or already swiped, for this kind

  @override
  Future<List<CatalogItem>> build(MediaKind kind) async {
    // Read once rather than watched, so a swipe does not rebuild the queue.
    final tracked = kind.isTv
        ? ref.read(trackedShowTmdbIdsProvider)
        : ref.read(trackedMovieTmdbIdsProvider);
    final prefix = '${kind.path}_';
    final seen = (ref.read(discoverSeenKeysProvider).value ?? const <String>{})
        .where((k) => k.startsWith(prefix))
        .map((k) => int.tryParse(k.substring(prefix.length)))
        .whereType<int>();
    _excluded
      ..addAll(tracked)
      ..addAll(seen);
    return _fetch(kind);
  }

  Future<List<CatalogItem>> _fetch(MediaKind kind) async {
    final tmdb = ref.read(tmdbApiProvider);
    if (tmdb == null) return const [];
    _page++;
    final batches = await Future.wait([
      tmdb.trending(kind, page: _page),
      tmdb.discover(kind, sort: CatalogSort.popular, page: _page),
    ]);
    final fresh = <CatalogItem>[];
    for (final card in [
      for (var i = 0; i < 20; i++)
        for (final b in batches)
          if (i < b.length) b[i], // interleave
    ]) {
      if (_excluded.contains(card.tmdbId) || !_loadedIds.add(card.tmdbId)) {
        continue;
      }
      fresh.add(card);
    }
    return fresh;
  }

  Future<void> loadMore() async {
    try {
      final more = await _fetch(kind);
      if (more.isNotEmpty) state = AsyncData([...?state.value, ...more]);
    } catch (_) {}
  }

  Future<void> like(CatalogItem card) async {
    _markSeen(card, liked: true);
    await ref.read(libraryAddProvider.notifier).add(card);
  }

  Future<void> pass(CatalogItem card) async => _markSeen(card, liked: false);

  void _markSeen(CatalogItem card, {required bool liked}) {
    _excluded.add(card.tmdbId);
    ref
        .read(trackingRepositoryProvider)
        ?.markDiscoverSeen('${card.kind.path}_${card.tmdbId}', liked: liked);
  }
}
