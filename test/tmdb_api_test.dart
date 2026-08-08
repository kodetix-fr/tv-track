import 'package:flutter_test/flutter_test.dart';
import 'package:tv_track/data/tmdb/catalog_item.dart';
import 'package:tv_track/data/tmdb/tmdb_api.dart';

import 'support/fake_tmdb.dart';

void main() {
  group('TmdbApi.search', () {
    test('a blank query never reaches the network', () async {
      final adapter = FakeTmdbAdapter((_) => null);
      final api = fakeTmdbApi(adapter);

      expect(await api.search(MediaKind.tv, ''), isEmpty);
      expect(await api.search(MediaKind.tv, '   '), isEmpty);
      expect(adapter.requests, isEmpty);
    });

    test('results are mapped into catalog items', () async {
      final adapter = FakeTmdbAdapter(
        (_) => {
          'results': [tvResult(1), tvResult(2)],
        },
      );

      final items = await fakeTmdbApi(adapter).search(MediaKind.tv, 'berlin');

      expect(items.map((e) => e.tmdbId), [1, 2]);
      expect(items.first.kind, MediaKind.tv);
      expect(adapter.requests.single.path, '/search/tv');
      expect(adapter.requests.single.queryParameters['query'], 'berlin');
    });
  });

  group('TmdbApi.discover', () {
    test('the configured language and watch region are sent', () async {
      final adapter = FakeTmdbAdapter((_) => null);
      final api = fakeTmdbApi(adapter, language: 'fr-FR', region: 'FR');

      await api.discover(MediaKind.tv);

      final params = adapter.requests.single.queryParameters;
      expect(params['language'], 'fr-FR');
      expect(params['watch_region'], 'FR');
    });

    test('a genre filter is passed through, and omitted when absent', () async {
      final adapter = FakeTmdbAdapter((_) => null);
      final api = fakeTmdbApi(adapter);

      await api.discover(MediaKind.tv, genreId: 18);
      await api.discover(MediaKind.tv);

      expect(adapter.requests.first.queryParameters['with_genres'], '18');
      expect(
        adapter.requests.last.queryParameters.containsKey('with_genres'),
        isFalse,
      );
    });

    test('top rated asks for a vote floor, other orders do not', () async {
      final adapter = FakeTmdbAdapter((_) => null);
      final api = fakeTmdbApi(adapter);

      await api.discover(MediaKind.tv, sort: CatalogSort.topRated);
      await api.discover(MediaKind.tv, sort: CatalogSort.popular);

      expect(adapter.requests.first.queryParameters['vote_count.gte'], 200);
      expect(
        adapter.requests.last.queryParameters.containsKey('vote_count.gte'),
        isFalse,
      );
    });
  });

  group('TmdbApi swipe deck lists', () {
    test('posterless entries are dropped', () async {
      final adapter = FakeTmdbAdapter(
        (_) => {
          'results': [tvResult(1), tvResult(2, poster: null), tvResult(3)],
        },
      );

      final items = await fakeTmdbApi(adapter).trendingTv();

      expect(items.map((e) => e.id), [1, 3]);
    });
  });

  group('TmdbApi.genres', () {
    test('a payload without genres yields an empty list', () async {
      final adapter = FakeTmdbAdapter((_) => const {});

      expect(await fakeTmdbApi(adapter).genres(MediaKind.tv), isEmpty);
    });

    test('genres are mapped to id and name', () async {
      final adapter = FakeTmdbAdapter(
        (_) => {
          'genres': [
            {'id': 18, 'name': 'Drama'},
          ],
        },
      );

      final genres = await fakeTmdbApi(adapter).genres(MediaKind.tv);

      expect(genres.single.id, 18);
      expect(genres.single.name, 'Drama');
    });
  });
}
