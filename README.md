# StreamApp

StreamApp is a Flutter media browsing and playback app with a local FastAPI backend.
It supports movies/series discovery, source resolution through add-ons, in-app playback,
watch history, a personal library, and runtime app settings.

## Highlights

- Flutter client for Windows/Android (plus default Flutter platform folders).
- Local FastAPI backend for stream resolution.
- Add-on manager (install, enable/disable, remove custom add-ons).
- Movie/series detail pages with source resolution and playback.
- Personal library (save/remove titles).
- Watch history with progress tracking.
- Settings screen:
  - App language (`English`, `Turkce`)
  - Subtitle language
  - TMDB access token (not hardcoded in repository)

## Tech Stack

- Flutter + Riverpod + Hive + Dio
- FastAPI + Uvicorn + httpx
- VLC/WebView-based playback depending on stream type/platform

## Project Structure

```text
stream_app/
  lib/
    core/
      i18n/
      settings/
      backend_bootstrap_service.dart
    features/
      home/
      search/
      player/
      library/
      addons/
      sources/
      settings/
  backend/
    main.py
    addons/
  android/
  windows/
```

## Prerequisites

- Flutter SDK (Dart included)
- Python 3.10+
- Windows build tools (for `flutter build windows`)
- Android SDK/Java (for `flutter build apk`)

For Windows build, `nuget.exe` must be available in `PATH`.

## Setup

1. Install Flutter dependencies:

```bash
flutter pub get
```

2. Install backend dependencies:

```bash
cd backend
pip install -r requirements.txt
```

3. Run app (Flutter will try to bootstrap local backend on desktop):

```bash
flutter run -d windows
```

Optional: run backend manually:

```bash
cd backend
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

## Settings and API Token

- Open the **Settings** tab in the app.
- Set your **TMDB Access Token**.
- Save settings.

The token is stored locally (Hive) and synced to backend at runtime.
No TMDB token is committed in source code.

## Build

### Windows EXE

```bash
flutter build windows --release
```

Output:

```text
build/windows/x64/runner/Release/stream_app.exe
```

### Android APK

```bash
flutter build apk --release
```

Output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## QA

Run static checks and tests:

```bash
flutter analyze
flutter test
```

## Notes

- If Windows build fails with file lock errors, close any running `stream_app.exe` and build again.
- If add-ons appear empty on first use, refresh once from the Add-ons screen.
