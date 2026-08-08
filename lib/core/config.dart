/// Build-time configuration.
///
/// Every value below is supplied with `--dart-define` so that nothing tied to a
/// specific Firebase project or API account lives in the repository. Each
/// feature degrades gracefully when its key is missing.
library;

/// OAuth "Web" client ID of the Firebase project, required by Google Sign-In on
/// Android:
///
///   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com
///
/// Left empty, the plugin falls back to the `default_web_client_id` string
/// resource generated from `google-services.json` — which requires a
/// `client_type: 3` entry in that file, and survives release builds only
/// because `android/app/src/main/res/raw/keep.xml` holds it against the
/// resource shrinker.
///
/// Both conditions fail silently at build time and surface as a sign-in error
/// on the device, so passing the value explicitly keeps the configuration
/// visible and reviewable.
///
/// This is not a secret: it ships inside the APK either way.
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// TMDB API key (v3). Powers the Discover catalog, global search, streaming
/// providers and poster artwork:
///
///   flutter run --dart-define=TMDB_API_KEY=xxxxx
///
/// Read-only and low sensitivity. Discover and search disable themselves when
/// the key is absent.
const tmdbApiKey = String.fromEnvironment('TMDB_API_KEY');

/// Streaming market used to resolve "where to watch" providers and regional
/// release dates, as an ISO 3166-1 country code. Separate from the interface
/// language: where you live is not what language you read in.
const watchRegion = String.fromEnvironment('WATCH_REGION', defaultValue: 'FR');

/// TheTVDB API key (v4), the primary metadata source for shows: season layout,
/// episode titles and overviews, artwork, air dates, status and network.
///
///   flutter run --dart-define=TVDB_API_KEY=xxxxx
///
/// Without it, show enrichment is skipped and the app keeps serving whatever is
/// already stored in Firestore.
const tvdbApiKey = String.fromEnvironment('TVDB_API_KEY');
