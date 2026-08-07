# Setup

This repository ships no Firebase configuration: to build the app you point it
at a Firebase project of your own. The free Spark plan is enough.

Replace `<your-project>` and `<your.package.id>` below with your own values.
The default package id used by this repo is `fr.kodetix.tvtrack`; if you change
it, update `android/app/build.gradle.kts` (`namespace` and `applicationId`) and
the iOS `PRODUCT_BUNDLE_IDENTIFIER` accordingly.

## 1. Create and link a Firebase project

1. Create a project on [console.firebase.google.com](https://console.firebase.google.com).
2. **Authentication → Sign-in method**: enable **Google**. This step has to be
   done in the console — it provisions the OAuth web client for you.
3. Create the database and deploy the security rules:
   ```sh
   gcloud services enable firestore.googleapis.com --project=<your-project>
   gcloud firestore databases create --location=europe-west1 --project=<your-project>
   firebase deploy --only firestore:rules --project=<your-project>
   ```
4. Generate the local configuration files (all gitignored):
   ```sh
   dart pub global activate flutterfire_cli
   flutterfire configure --project=<your-project> --platforms=android \
     --android-package-name=<your.package.id> --yes
   ```
5. Register the SHA-1 and SHA-256 fingerprints of your debug keystore under
   *Project settings → Your apps → Android → Add fingerprint*. Google Sign-In
   rejects the app until they are present:
   ```sh
   keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android \
     | openssl x509 -inform DER -fingerprint -sha1 -noout
   ```
   Then download `google-services.json` again (or re-run `flutterfire configure`)
   so it includes the OAuth clients.

## 2. Run

```sh
flutter pub get
dart run build_runner build
flutter run --dart-define=TMDB_API_KEY=xxxxx --dart-define=TVDB_API_KEY=xxxxx
```

Both keys are free:

| Key | Where to get it | What breaks without it |
|---|---|---|
| `TVDB_API_KEY` | [thetvdb.com/api-information](https://thetvdb.com/api-information) | Show metadata enrichment (seasons, episodes, artwork) |
| `TMDB_API_KEY` | [themoviedb.org → Settings → API](https://www.themoviedb.org/settings/api) | Discover, global search, streaming providers |

Both degrade gracefully: the app still runs on whatever is already stored in
Firestore, with the affected features disabled.

### UI preview without Firebase

Renders the screens against sample data, so no Firebase project is needed:

```sh
flutter run -t lib/preview_main.dart --dart-define=TMDB_API_KEY=xxxxx
# variants: --dart-define=PREVIEW=detail|movie|search
```

### Seeding a TV Time export (one-shot, outside the app)

1. Sign in once in the app, which creates the Firebase Auth user.
2. Grab the UID from *Firebase console → Authentication → Users*, or:
   ```sh
   firebase auth:export /dev/stdout --format=json --project=<your-project>
   ```
3. Import the export:
   ```sh
   dart run tool/seed_tvtime.dart --uid <UID> \
     --series tvtime-series-<date>.json \
     --movies tvtime-movies-<date>.json
   ```

The script reuses the app's tested parser and writes through the Firestore REST
API with your `gcloud` token, so IAM applies and the security rules are bypassed.
It is idempotent: one document per `tvdbId`, safe to re-run.

## 3. CI: CI → Firebase App Distribution

Connect the repository in CI; `the release workflow` is picked up
automatically. Create a variable group named **`firebase`** (encode file values
with `base64 -i <file>`):

| Variable | Contents | Secure |
|---|---|---|
| `FIREBASE_ANDROID_APP_ID` | Firebase Android app ID (`1:…:android:…`) | no |
| `ANDROID_KEY_ALIAS` | key alias inside the release keystore | no |
| `GOOGLE_SERVICES_JSON` | base64 of `android/app/google-services.json` | yes |
| `FIREBASE_OPTIONS_DART` | base64 of `lib/firebase_options.dart` | yes |
| `ANDROID_KEYSTORE` | base64 of the release keystore | yes |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password | yes |
| `FIREBASE_SERVICE_ACCOUNT` | JSON key of a service account with the *Firebase App Distribution Admin* role | yes |
| `TMDB_API_KEY` | TMDB v3 API key | yes |
| `TVDB_API_KEY` | TheTVDB v4 API key | yes |

Two things also need to exist on the Firebase side:

- the SHA-1 and SHA-256 of the **release** keystore, registered like the debug
  ones in step 1.5;
- a tester group named **`testers`** in App Distribution — that alias is what
  `the release workflow` publishes to.

### Creating the release keystore and service account

```sh
keytool -genkeypair -v -keystore release.keystore -alias <your-alias> \
  -keyalg RSA -keysize 2048 -validity 10000

gcloud iam service-accounts create app-distribution \
  --display-name="App Distribution" --project=<your-project>
gcloud projects add-iam-policy-binding <your-project> \
  --member="serviceAccount:app-distribution@<your-project>.iam.gserviceaccount.com" \
  --role="roles/firebaseappdistro.admin" --condition=None
gcloud iam service-accounts keys create service-account.json \
  --iam-account=app-distribution@<your-project>.iam.gserviceaccount.com
```

Store the keystore and its password outside the repository and back them up:
losing the keystore means you can no longer update an installed build. Once both
files are loaded into CI variables, delete the local service account key.

Every push to `main` then runs codegen → tests → signed APK → distribution to
the `testers` group.
