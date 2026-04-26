# StreamApp — Proje Rehberi (Agent Reference)

> Bu dosya AI agent'ların projeyi hızlıca anlaması için oluşturulmuştur.
> Son güncelleme: 2026-04-26

## Genel Bakış
StreamApp, Flutter tabanlı bir medya tarama ve oynatma uygulamasıdır. Metadata TMDB üzerinden alınır, gerçek oynatma kaynakları FastAPI backend üzerinde addon mimarisi ile çözülür. Sistem Stremio manifest/addon URL'lerini destekler, ayrıca doğrudan dizi/film sayfası linklerinden stream adayları çıkarabilen web-source addon tipini içerir. Desktop açılışında backend otomatik başlatılır ve VidSrc embed oynatımında altyazı dili kullanıcı seçimine göre ayarlanır.

## Klasör Yapısı
```
stream_app/
├─ lib/
│  ├─ main.dart (~40) - Uygulama başlatma, Hive init
│  ├─ core/backend_bootstrap_service.dart (~130) - Desktop backend auto-start ve sağlık kontrolü
│  ├─ features/home/presentation/screens/home_screen.dart (~42) - Alt sekme yapısı
│  ├─ features/home/presentation/screens/home_content.dart (~107) - Trend/kategori içerik listeleri
│  ├─ features/home/presentation/providers/home_provider.dart (~26) - Ana sayfa provider'ları
│  ├─ features/search/data/repositories/search_repository.dart (~126) - TMDB entegrasyonu
│  ├─ features/search/domain/entities/media_item.dart (~80) - Media, season, episode modelleri
│  ├─ features/search/presentation/providers/search_provider.dart (~37) - Search provider'ları
│  ├─ features/search/presentation/screens/search_screen.dart (~92) - Arama sonucu listesi
│  ├─ features/search/presentation/screens/media_details_screen.dart (~450) - İçerik detayı + kaynak çözümleme + altyazı dili seçimi
│  ├─ features/player/presentation/screens/player_screen.dart (~280) - Player, backend fallback ve embed altyazı dili uygulama
│  ├─ features/player/data/repositories/watch_history_repository.dart (~30)
│  ├─ features/player/domain/entities/watch_history.dart (~29)
│  ├─ features/addons/presentation/screens/addon_manager_screen.dart (~320) - Addon/kaynak yönetimi
│  ├─ features/sources/presentation/screens/sources_screen.dart (~132) - Yerel kaynak kayıt ekranı
│  ├─ features/sources/data/repositories/sources_repository.dart (~30)
│  └─ features/sources/data/models/source_model.dart (~53)
├─ backend/
│  ├─ main.py (~330) - API endpointleri (`/api/resolve`, `/api/stream`, `/api/search`)
│  ├─ addons/base.py (~48) - Addon contract ve DTO'lar
│  ├─ addons/manager.py (~520) - Addon install/remove/toggle, Stremio uyumluluk
│  ├─ addons/websource.py (~280) - Direkt site linklerinden stream çıkarma
│  ├─ addons/jellyfin.py (~85) - Jellyfin addon
│  ├─ addons/archiveorg.py (~78) - Archive.org addon
│  ├─ addons/webtorrent.py (~100) - WebTorrent demo addon
│  ├─ addons_config.json (~11) - Persist edilen addon durumları
│  ├─ example_addon_server.py (~93) - Örnek custom addon
│  └─ requirements.txt (~3)
├─ android/app/src/main/AndroidManifest.xml (~41)
├─ ios/Runner/Info.plist (~58)
├─ pubspec.yaml (~81)
└─ test/widget_test.dart (~24)
```

## Veritabanı Şeması
İlişkisel veritabanı kullanılmıyor.

Depolama katmanları:
- Flutter Hive `sources_box`: `id`, `name`, `baseUrl`, `searchEndpoint`, `isEnabled`
- Flutter Hive watch history box: izleme ilerleme verisi
- Backend JSON `backend/addons_config.json`:
  - `enabled`: addon_id -> bool
  - `custom_urls`: addon_id -> url

## Önemli Modeller
- `MediaItem`, `Season`, `Episode`: `lib/features/search/domain/entities/media_item.dart`
- `WatchHistory`: `lib/features/player/domain/entities/watch_history.dart`
- `Source`: `lib/features/sources/domain/entities/source.dart`
- `AddonManifest`, `SearchResult`, `StreamResult`: `backend/addons/base.py`
- Internal web source adayı: `_CandidateItem` (`backend/addons/websource.py`)

## State Management
Riverpod tabanlı:
- Arama: `searchQueryProvider`, `searchResultsProvider`, `seriesSeasonsProvider`, `seasonEpisodesProvider`
- Home: trend/genre FutureProvider'ları
- Addon: `addonsProvider` (`AddonsNotifier`)
- Kaynaklar: `sourcesProvider` (`SourcesNotifier`)
- Watch history: repository provider

## Ekran/Route Haritası
```
HomeScreen
├─ HomeContent
│  └─ MediaDetailsScreen
│     └─ PlayerScreen
├─ SearchScreen
│  └─ MediaDetailsScreen
│     └─ PlayerScreen
├─ LibraryScreen
├─ SourcesScreen
└─ AddonManagerScreen
```

## Bağımlılıklar
| Paket | Versiyon | Amaç |
|---|---|---|
| flutter_riverpod | ^3.3.1 | State management |
| dio | ^5.9.2 | HTTP istemcisi |
| hive / hive_flutter | ^2.2.3 / ^1.1.0 | Yerel veri saklama |
| flutter_vlc_player | ^7.4.4 | Video oynatma |
| webview_flutter / webview_windows | ^4.8.0 / ^0.4.0 | Uygulama içi embed oynatma (mobil + Windows) |
| fastapi | latest | Backend API |
| uvicorn | latest | ASGI server |
| httpx | latest | Addon/network çağrıları |

## Platform İzinleri
| İzin | Durum (Android/iOS/Windows) |
|---|---|
| INTERNET | ❌ Android manifestte açıkça tanımlı değil |
| Ağ durum izni | ❌ |
| iOS medya/network açıklama key'leri | ❌ |
| Windows özel izin bildirimi | ❌ |

## API Entegrasyonları
- TMDB (`api.themoviedb.org`): metadata/trend/search/season
- StreamApp backend (`127.0.0.1:8000`):
  - `GET /api/addons`
  - `POST /api/addons/install`
  - `POST /api/addons/remove/{addon_id}`
  - `POST /api/addons/toggle`
  - `GET /api/search`
  - `GET /api/resolve`
  - `GET /api/stream`
  - `GET /api/health`
- Addon protokolleri:
  - Custom: `/manifest.json`, `/search`, `/stream`
  - Stremio: `/manifest.json`, `/catalog/...`, `/stream/{type}/{id}.json`
  - Web Source: direkt page/media URL

## Bilinen Sorunlar / Teknik Borç
1. TMDB token hem Flutter hem backend içinde gömülü; env/config'e taşınmalı.
2. Android/iOS izinleri production kullanımına göre netleştirilmeli.
3. SourcesScreen yerel kayıt tutuyor; backend addon sync akışıyla tam birleştirme gerekebilir.
4. Flutter CLI PATH yoksa yerel doğrulama komutları çalışmıyor.
5. Backend auto-start yalnızca desktop senaryoları için tasarlandı; mobil/web için uzak backend stratejisi gerekebilir.

## Build & Çalıştırma
```bash
# Flutter
flutter pub get
flutter run

# Android APK Build
C:\flutter\bin\flutter.bat build apk --release

# Windows EXE Build
C:\flutter\bin\flutter.bat build windows --release

# Backend
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

## Kodlama Kuralları
- Yeni kaynak entegrasyonları backend tarafında `BaseAddon` sözleşmesine uymalı.
- UI sadece çözümleme/oynatma akışını yönetmeli; iş kuralları backend'de kalmalı.
- Stremio URL varyasyonları normalize edilmeden doğrudan kullanılmamalı.
- Ağ/API hataları kullanıcıya anlamlı Türkçe mesajla dönmeli.
