import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'config.dart';

/// Dio client for one provider path of the metadata proxy (`tmdb` or `tvdb`).
///
/// The proxy rejects anonymous callers, so every request carries the caller's
/// Firebase ID token. `getIdToken` serves a cached token and refreshes it on its
/// own once expired.
Dio metadataProxyDio(String provider, {required FirebaseAuth auth}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: '$metadataProxyUrl/$provider',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await auth.currentUser?.getIdToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );
  return dio;
}
