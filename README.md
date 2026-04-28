# StreamApp

StreamApp is a Flutter media browsing and playback app with a local FastAPI backend.
It supports movies/series discovery, source resolution through add-ons, in-app playback,
watch history, a personal library, and runtime app settings.

## Highlights

- Flutter client for Windows/Android (plus default Flutter platform folders).
- Local FastAPI backend for stream resolution.
- Add-on manager (install, enable/disable, remove custom add-ons).
- Add-on manager supports install from URL and local `.json` manifest file.
- Movie/series detail pages with source resolution and playback.
- Personal library (save/remove titles).
- Watch history with progress tracking.
- Settings screen:
  - App language (`English`, `Turkce`)
  - Subtitle language
  - TMDB access token (not hardcoded in repository)
  - Source auto-selection (avoid asking source every play)
  - Preferred source selection
  - Source/Add-on management pages

## Tech Stack

- Flutter + Riverpod + Hive + Dio
- FastAPI + Uvicorn + httpx
- VLC/WebView-based playback depending on stream type/platform

## Download

### Android

| Architecture | File | Size |
|-------------|------|------|
| ARM64 (most devices) | [app-arm64-v8a-release.apk](https://github.com/serdevir91/stream_app/releases/download/v1.0.1/app-arm64-v8a-release.apk) | ~61 MB |
| ARM 32-bit (older devices) | [app-armeabi-v7a-release.apk](https://github.com/serdevir91/stream_app/releases/download/v1.0.1/app-armeabi-v7a-release.apk) | ~54 MB |
| x86_64 (emulators) | [app-x86_64-release.apk](https://github.com/serdevir91/stream_app/releases/download/v1.0.1/app-x86_64-release.apk) | ~68 MB |

> Most modern phones use ARM64. If unsure, download the ARM64 version.

### Windows

| Type | File | Size |
|------|------|------|
| Installer (recommended) | [StreamApp-Setup-v1.0.1.exe](https://github.com/serdevir91/stream_app/releases/download/v1.0.1/StreamApp-Setup-v1.0.1.exe) | ~11 MB |
| Portable | [stream_app-windows-x64.zip](https://github.com/serdevir91/stream_app/releases/download/v1.0.1/stream_app-windows-x64.zip) | ~13 MB |

**Installer**: Run the `.exe` wizard. Creates Start Menu shortcuts and an uninstaller.

**Portable**: Extract the ZIP and run `stream_app.exe` directly. No installation needed.

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
- Configure source behavior:
  - `Auto play best source` enabled: app starts playback directly.
  - `Preferred Source`: pick a specific add-on, or leave Auto.
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

### Windows Installer

Requires [Inno Setup 6](https://jrsoftware.org/isinfo.php).

```bash
# Build Windows release first
flutter build windows --release

# Compile installer
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\stream_app.iss
```

Output: `output/StreamApp-Setup-v1.0.1.exe`

### Android APK

```bash
# Single APK (all architectures, ~180MB)
flutter build apk --release

# Split APKs by architecture (recommended, ~55-70MB each)
flutter build apk --split-per-abi --release
```

Output:

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
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

## Built-in Add-ons

StreamApp ships with the following source add-ons:

| Add-on | Type | Description |
|--------|------|-------------|
| **VidSrc** | Embed | Multi-source embed provider |
| **TwoEmbed** | Embed | 2embed.cc streaming source |
| **SuperEmbed** | Embed | SuperEmbed embed provider |
| **VidLink** | Embed | VidLink embed provider |
| **EmbedSU** | Embed | Embed.su streaming source |
| **FlixHQ** | API/Scraping | FlixHQ movie/series source |
| **Archive.org** | API | Internet Archive content (disabled by default) |
| **WebTorrent** | API | WebTorrent-based streaming (disabled by default) |
| **Jellyfin** | API | Jellyfin media server integration (disabled by default) |

## Add-on Creation Guide

Other users can create and share add-ons by publishing a compatible backend API.

### 1. Required Manifest JSON

Create `manifest.json`:

```json
{
  "id": "community.example",
  "name": "Community Example Addon",
  "description": "Sample addon for Stream App",
  "version": "1.0.0",
  "types": ["movie", "series"],
  "transportUrl": "https://your-addon-domain.com",
  "icon": "film"
}
```

`transportUrl` is required when installing from a local file.

### 2. Required API Endpoints

Your backend must expose:

- `GET /search?query=<text>&type=movie|series`
- `GET /stream?id=<contentId>&type=movie|series&season=<n>&episode=<n>`

`/search` response:

```json
{
  "results": [
    {
      "id": "movie_123",
      "title": "Example Movie",
      "type": "movie",
      "year": "2024",
      "poster": "https://.../poster.jpg",
      "description": "Optional"
    }
  ]
}
```

`/stream` response:

```json
{
  "streams": [
    {
      "url": "https://.../playlist.m3u8",
      "title": "Example Stream",
      "quality": "1080p",
      "provider": "Example",
      "is_direct_link": true
    }
  ]
}
```

### 3. Install in App

- Open `Settings -> Add-ons`.
- Choose one:
  - `Install from URL` and provide addon manifest URL.
  - `Install from file (.json)` and choose local manifest file.

## Changelog

### v1.0.1

- **New Add-ons**: SuperEmbed, TwoEmbed, VidLink, EmbedSU, FlixHQ
- **Redesigned Home Screen**: Featured content slider with trending movies/series
- **Improved Search**: Genre filtering, pagination, better results layout
- **Enhanced Player**: Better subtitle support, improved controls, VLC/WebView switching
- **Redesigned Settings**: Organized sections, better UX
- **Addon Manager**: Improved install/remove flow, URL and file-based install
- **Watch History**: Better progress tracking, resume playback
- **i18n**: Updated English and Turkish translations
- **Bug Fixes**: Various stability improvements

### v1.0.0

- Initial release
- TMDB integration for movie/series discovery
- Basic add-on system with VidSrc
- VLC and WebView playback
- Personal library and watch history
- Windows and Android support

## License

MIT License
