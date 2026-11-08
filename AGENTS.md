# Stream App — agent notes

Flutter app (Riverpod 3, Hive, Dio, media_kit). Movies/series via TMDB metadata plus
Stremio-style addons, anime extensions, downloads, subtitles. Distributed as APKs on
GitHub Releases (not on Play). Repo: `serdevir91/stream_app`.

## Layout
- `lib/core/backend/addon_service.dart` — source resolver. `resolveStream()` runs all
  addons in parallel (8 s each), streams progress, 20 min cache, shared jobs;
  `resolveFast()` returns on a trusted source or after a 3 s grace.
- `lib/core/backend/source_ranking.dart` — `SourceStats` (Hive `source_stats_box`),
  reliability and ranking.
- `lib/core/subtitles/` — subtitle engine (SRT/VTT/ASS, cp1254, fps-drift fix). The
  overlay is the only renderer; players' own subtitle tracks stay off.
- `lib/core/player/` — external player channel (`stream_app/external_player`),
  local proxy/subtitle server.
- `lib/features/downloads/` + download service — foreground service, HLS with
  resume, `.part` files, subtitles saved next to the video.
- `lib/core/theme/app_theme.dart` — light / dark / AMOLED. `theme_x.dart` has
  `context.fg/fgMuted/fgFaint/line/card/bg` and `DarkScope` (keeps poster/player
  screens dark in light mode). Use these instead of `Colors.white*` in new code.
- `lib/core/app_baseline.dart` — GitHub update check, review prompt (GitHub star),
  support link (hidden while `donationUrl` is empty). No IAP in the GitHub build.
- Text: `lib/core/i18n/app_text.dart` (`text.t('key')`, en + tr full, ar/fa partial).

## Build and test
- `flutter analyze` and `flutter test` must be clean.
- Emulator on the Mac mini is arm64 (`Pixel_9_API_36`):
  `flutter build apk --debug --target-platform android-arm64`. Emulator storage is
  tight; uninstall before installing a new debug APK.
- Release: `flutter build apk --release` (universal `app-release.apk`) then
  `flutter build apk --split-per-abi --release`. Never in parallel.

## Signing (important)
- Since v1.0.29 releases are signed with `~/SigningBackup/stream_app/stream-release.jks`
  (cert SHA-256 `c8e04e6e1c22…`). Copy `~/SigningBackup/stream_app/key.properties` to
  `android/key.properties` (gitignored) before a release build.
- Without that file, release builds use the debug key and cannot update installed copies.
- Releases up to 1.0.28 used another key (`d5ac6ce5…`) whose password is lost; 1.0.28
  users had to uninstall once.

## Release
- Bump `pubspec.yaml` (`x.y.z+n` → `x.y.(z+1)+(n+1)`), tag `vX.Y.Z`, GitHub Release
  with the four APKs (+ Windows installer when built on the Windows laptop), release
  notes in `<en-US>…</en-US>`, update the README download table.
