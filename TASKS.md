# stream_app — Görev Listesi

> Son güncelleme: 2026-04-26

---

## Görevler

### 1. 🚀 Addon ve stream akışını stabilize et
- [x] Backend addon kurulum ve Stremio uyumluluk akışını güçlendir
- [x] Addon arama/stream fallback zincirindeki kırılmaları düzelt
- [x] Hata mesajlarını kullanıcı dostu hale getir

### 2. 🎬 Direkt dizi/film site linklerinden kaynak üret
- [x] Backend'e doğrudan URL kaynak çözümleyici ekle
- [x] URL'den stream adaylarını çıkarıp kaynak olarak kaydet
- [x] Flutter addon ekranına "site linki ekle" akışını bağla

### 3. 📺 Dizi/film detayında kaynak çözümleme
- [x] Detay ekranında stream adaylarını listele
- [x] Kullanıcının seçtiği kaynaktan oynatma başlat
- [x] Arama ekranından detay ekranına geçişi düzelt

### 4. ✅ Doğrulama ve dokümantasyon
- [x] Flutter/backend temel doğrulama komutlarını çalıştır
- [x] TASKS.md tamamlanma durumunu güncelle
- [x] Değişen dosyalar listesini doldur

### 5. 🎬 Oynatmayı uygulama içinde tut
- [x] Tarayıcıya yönlendiren player akışını kaldır
- [x] Embed/vidsrc içeriğini uygulama içi webview ile aç
- [x] Player ve görev dosyalarında değişiklikleri doğrula

### 6. ✅ Aktif addon görünmeme düzeltmesi
- [x] Backend çalışmadığı durumda nedeni doğrula
- [x] Backend API'yi tekrar ayağa kaldır ve addonları doğrula
- [x] Yerleşik addon kayıtlarını backend başlangıcında geri yükle

### 7. ⚙️ Açılış ve kaynak deneyimi iyileştirme
- [x] Uygulama açılışında backend'i otomatik başlat
- [x] VidSrc embed için altyazı dilini seçilebilir yap
- [x] Ana ekrandaki sorunlu VidSrc latest bloklarını kaldır

### 8. 📦 Uygulama Paketleme
- [x] Android APK (Release) build et
- [x] Windows EXE (Release) build et

### 9. 📱 Standalone Android (PC-siz Çalışma)
- [x] Dart üzerinde `InternalBackendService` geliştirildi (VidSrc resolver)
- [x] Addon ve Player ekranlarına fallback mekanizması eklendi
- [x] Android APK için internet izinleri ve Cleartext traffic (HTTP) ayarları yapıldı
- [x] Derleme hataları (import/parametre) düzeltildi
- [x] WebView `ERR_HTTP2_PROTOCOL_ERROR` hatası için Custom User-Agent ve NavigationDelegate eklendi ✅
- [x] Standalone APK build edildi ✅

---

## Tamamlanma Durumu: 29/29 ✅

## Değişen Dosyalar
- AGENT.md: Proje rehberi güncellendi, yeni addon/resolve akışı eklendi
- TASKS.md: Görev ilerleme ve tamamlanma durumu güncellendi
- backend/addons/websource.py: Direkt site/link kaynağından stream çıkaran yeni addon eklendi
- backend/addons/manager.py: Stremio uyumluluğu güçlendirildi, URL normalize ve web source fallback eklendi
- backend/main.py: `/api/resolve` endpoint'i ve gelişmiş stream çözümleme zinciri eklendi
- lib/features/search/presentation/screens/media_details_screen.dart: Kaynak çözümleme ve stream seçim bottom sheet eklendi
- lib/features/player/presentation/screens/player_screen.dart: Önceden çözümlenmiş stream URL ile direkt oynatma desteği eklendi
- lib/features/search/presentation/screens/search_screen.dart: Arama sonucundan detay ekranına yönlendirme düzeltildi
- lib/features/addons/presentation/screens/addon_manager_screen.dart: Boş durum ve site linki/manifest giriş metinleri iyileştirildi
- lib/features/home/presentation/screens/home_screen.dart: Kaynaklar sekmesi alt navigasyona eklendi
- lib/features/player/presentation/screens/player_screen.dart: Embed içerik dış tarayıcı yerine uygulama içi WebView/WebView2 ile açılacak şekilde güncellendi
- pubspec.yaml: Windows için uygulama içi embed oynatma desteği adına `webview_windows` bağımlılığı eklendi
- pubspec.lock: Yeni bağımlılık kilit dosyasına işlendi (`webview_windows 0.4.0`)
- backend/main.py: Başlangıçta yerleşik addonların (VidSrc, ArchiveOrg, WebTorrent, Jellyfin) otomatik kaydı geri eklendi
- lib/core/backend_bootstrap_service.dart: Desktop açılışında backend sağlık kontrolü ve otomatik uvicorn başlatma servisi eklendi
- lib/main.dart: Uygulama başlamadan backend auto-start akışı entegre edildi
- lib/features/search/presentation/screens/media_details_screen.dart: Altyazı dili seçimi eklendi ve PlayerScreen'e aktarım yapıldı
- lib/features/player/presentation/screens/player_screen.dart: VidSrc embed URL'lerinde `ds_lang` parametresi seçili dile göre dinamik hale getirildi
- lib/features/home/presentation/screens/home_content.dart: VidSrc Latest Movies/Series bölümleri kaldırıldı
- lib/features/home/presentation/providers/home_provider.dart: VidSrc latest provider'ları kaldırıldı
- AGENT.md: Dosya ismi büyük harfe çevrildi ve içerik düzenlendi
- TASKS.md: Build görevleri eklendi ve tamamlandı
- build/app/outputs/flutter-apk/app-release.apk: Android release paketi oluşturuldu
- build/windows/x64/runner/Release/stream_app.exe: Windows release paketi oluşturuldu
- lib/core/backend/internal_backend.dart: Standalone Android için yerel resolver servisi eklendi
- android/app/src/main/AndroidManifest.xml: Insecure HTTP için cleartext traffic izni eklendi
- lib/features/addons/presentation/screens/addon_manager_screen.dart: Yerel fallback entegre edildi
- lib/features/player/presentation/screens/player_screen.dart: Yerel stream resolver fallback eklendi
