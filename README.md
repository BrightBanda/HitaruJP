# HitaruJP

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Deploying the web app

`render.yaml` is a Render Blueprint for the web build, as a static site.
In Render choose **New → Blueprint** and pick this repository.

- The build (`tool/render_build_web.sh`) installs the Flutter version pinned in
  `render.yaml`. Keep `FLUTTER_VERSION` in step with `flutter --version`.
- `API_BASE_URL` in `render.yaml` is the API the site talks to. It is baked in at
  build time, so redeploy after changing it.
- The API is deployed separately, from its own Blueprint in
  `Ingrained_backend/render.yaml`.
- After the first deploy, add the site's domain in the Firebase console under
  **Authentication → Settings → Authorized domains**, or Google sign-in fails.
- Not available on web: Anki import (mobile only), YouTube search, and
  transcripts. Browsers block requests to youtube.com from other sites.

## Android release setup

The Android application ID is `com.hautek.hitarujp`, set in `android/app/build.gradle.kts`.
It is permanent once the app is published.

1. **Register the app in Firebase.** In project `ingrain-58270`, add an Android app
   with package name `com.hautek.hitarujp`.
2. **Add signing fingerprints.** Add the SHA-1 and SHA-256 of every key that signs the
   app to that Firebase Android app: debug, upload, and Google Play's app signing key.
   Google sign-in fails for any build whose key is missing. To print them:
   `cd android && ./gradlew signingReport`
3. **Regenerate the Firebase config.**
   `flutterfire configure --project=ingrain-58270 --platforms=android,web`
   This rewrites `android/app/google-services.json`, `lib/firebase_options.dart` and
   `firebase.json`.
4. **Create an upload key** (once, and back it up):
   `keytool -genkey -v -keystore ~/keys/hitarujp-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
   Then copy `android/key.properties.example` to `android/key.properties` and fill it in.
   Without that file, release builds are signed with the debug key, which the Play
   Store rejects.
5. **Build:** `flutter build appbundle --release`

## App icon

The icon's source is `branding/app_icon.svg`. `app_icon_monochrome.svg` is the version for
Android themed icons, and `app_icon_mark.svg` is the simplified favicon. After editing,
regenerate every Android, web and Play Store icon:

    bash tool/generate_icons.sh

This needs ImageMagick with librsvg and the Noto Sans CJK JP font, which draws 浸. The Play
Store listing icon is written to `branding/store/play_store_icon_512.png`.
