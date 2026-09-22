import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_text.dart';
import '../settings/app_settings_provider.dart';

class OnboardingTutorialDialog extends ConsumerStatefulWidget {
  const OnboardingTutorialDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const OnboardingTutorialDialog(),
    );
  }

  @override
  ConsumerState<OnboardingTutorialDialog> createState() =>
      _OnboardingTutorialDialogState();
}

class _OnboardingTutorialDialogState
    extends ConsumerState<OnboardingTutorialDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _finishTutorial() {
    final settings = ref.read(appSettingsProvider);
    ref
        .read(appSettingsProvider.notifier)
        .saveSettings(settings.copyWith(hasSeenTutorial: true));
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final isTr = text.languageCode == 'tr';
    final isAr = text.languageCode == 'ar';
    final isFa = text.languageCode == 'fa';

    final slides = [
      _TutorialSlideData(
        icon: Icons.playlist_play_rounded,
        color: Colors.purpleAccent,
        title: isTr
            ? 'Akıllı Sezon Geçişi'
            : isAr
                ? 'الانتقال الذكي للمواسم'
                : isFa
                    ? 'انتقال هوشمند فصل‌ها'
                    : 'Smart Season Rollover',
        description: isTr
            ? 'Dizi sezonunuz bittiğinde uygulama otomatik olarak sıradaki yeni sezona geçer. Kaldığınız yerden kesintisiz izlemeye devam edin!'
            : isAr
                ? 'عند انتهاء الموسم، ينتقل التطبيق تلقائياً للموسم التالي بدون توقف!'
                : isFa
                    ? 'پس از اتمام فصل سریال، برنامه به صورت خودکار به فصل بعد منتقل می‌شود.'
                    : 'When a season ends, continue watching automatically advances to Season 2 Episode 1 seamlessly.',
      ),
      _TutorialSlideData(
        icon: Icons.style_rounded,
        color: Colors.amberAccent,
        title: isTr
            ? 'Keşfet Swipe Kartları'
            : isAr
                ? 'بطاقات الاستكشاف'
                : isFa
                    ? 'کارت‌های کشف'
                    : 'Discover Swipe Cards',
        description: isTr
            ? 'Letterboxd ve Tinder tarzı kartlar! Sağa kaydır: İzledim, Sola kaydır: Listeme Ekle. Korku, aksiyon gibi türleri seçip IMDb puanına göre keşfe çıkın.'
            : isAr
                ? 'اسحب يميناً لوضعها كمشاهدة، ويساراً لإضافتها لقائمتك، مع فلترة حسب النوع وتقييم IMDb!'
                : isFa
                    ? 'کارت‌های تعاملی! برای تماشا به راست بکشید، برای افزودن به لیست به چپ، همراه با فیلتر ژانر و نمره IMDb.'
                    : 'Tinder & Letterboxd style swipe deck! Swipe right for Watched, swipe left for My List. Filter by genre and IMDb ratings.',
      ),
      _TutorialSlideData(
        icon: Icons.download_for_offline_rounded,
        color: Colors.cyanAccent,
        title: isTr
            ? 'IDM İndirme ve Tüm Sezon'
            : isAr
                ? 'تحميل الحلقات والمواسم'
                : isFa
                    ? 'دانلود قسمت‌ها و کل فصل'
                    : 'Download Manager & Full Season',
        description: isTr
            ? 'İstediğiniz kaliteyi (1080p, 720p) seçip indirin! Dilerseniz "Tüm Sezonu İndir" ile tek tıkla tüm bölümleri sıraya alın. Çevrimdışı dilediğiniz an izleyin.'
            : isAr
                ? 'اختر الجودة المطلوبة وحمل الأفلام أو مواسم كاملة بضغطة واحدة للمشاهدة بدون إنترنت.'
                : isFa
                    ? 'کیفیت مورد نظر را انتخاب و فیلم یا کل فصل را با یک کلیک برای تماشای آفلاین دانلود کنید.'
                    : 'Select video quality and download movies or entire TV seasons with one tap. Watch offline anytime!',
      ),
      _TutorialSlideData(
        icon: Icons.subtitles_rounded,
        color: Colors.greenAccent,
        title: isTr
            ? 'Otomatik Altyazı Eşleme'
            : isAr
                ? 'مطابقة الترجمة التلقائية'
                : isFa
                    ? 'هماهنگی خودکار زیرنویس'
                    : 'Auto Subtitle Matcher',
        description: isTr
            ? 'İndirilen tüm içeriklerin altyazısı arka planda otomatik olarak aranır, seçtiğiniz dilde indirilip videoyla birebir eşleştirilir.'
            : isAr
                ? 'يتم البحث عن ملفات الترجمة وتنزيلها تلقائياً لمطابقة الفيديو دون تدخل منك.'
                : isFa
                    ? 'زیرنویس هماهنگ به صورت خودکار دانلود و به فایل ویدیوی شما متصل می‌شود.'
                    : 'Downloaded media automatically searches, fetches, and pairs matching subtitles (.srt) for offline playback.',
      ),
      _TutorialSlideData(
        icon: Icons.backup_rounded,
        color: Colors.deepOrangeAccent,
        title: isTr
            ? 'Tam Yedekleme ve Oynatıcı'
            : isAr
                ? 'النسخ الاحتياطي والمشغل'
                : isFa
                    ? 'پشتیبان‌گیری کامل و پلیر'
                    : 'Full Backup & Player Engines',
        description: isTr
            ? 'İzleme listeniz ve izledikleriniz eksiksiz JSON olarak yedeklenir. ExoPlayer ve MediaKit (MPV) motorları, AMOLED saf siyah tema ile tam kontrol sizde!'
            : isAr
                ? 'نسخ احتياطي كامل لقائمتك وسجلك كملف JSON، مع دعم شاشات AMOLED ومحركات تشغيل متطورة.'
                : isFa
                    ? 'پشتیبان‌گیری کامل از لیست و تاریخچه به صورت JSON همراه با تم مشکی AMOLED و موتورهای پخش قدرتمند.'
                    : 'Complete JSON backup for your list and watched history. Native & MediaKit players, plus AMOLED black mode.',
      ),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF14141E) : Colors.white;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: dialogBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 540),
        child: Column(
          children: [
            // Top Bar with Skip Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Stream App',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _finishTutorial,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                    ),
                    child: Text(
                      isTr
                          ? 'Atla'
                          : isAr
                              ? 'تخطي'
                              : isFa
                                  ? 'رد کردن'
                                  : 'Skip',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            // PageView Content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: slides.length,
                onPageChanged: (idx) {
                  setState(() {
                    _currentPage = idx;
                  });
                },
                itemBuilder: (context, idx) {
                  final slide = slides[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: slide.color.withValues(alpha: 0.15),
                            border: Border.all(
                              color: slide.color.withValues(alpha: 0.4),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: slide.color.withValues(alpha: 0.25),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            slide.icon,
                            color: slide.color,
                            size: 46,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          slide.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Indicator Dots & Navigation Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _currentPage == index ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? Theme.of(context).colorScheme.primary
                              : (isDark ? Colors.white24 : Colors.black12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Bottom buttons
                  Row(
                    children: [
                      if (_currentPage > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              side: BorderSide(
                                color: isDark ? Colors.white24 : Colors.black12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              isTr
                                  ? 'Geri'
                                  : isAr
                                      ? 'السابق'
                                      : isFa
                                          ? 'قبلی'
                                          : 'Back',
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      if (_currentPage > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_currentPage < slides.length - 1) {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              _finishTutorial();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _currentPage == slides.length - 1
                                ? (isTr
                                    ? 'Hemen Başla'
                                    : isAr
                                        ? 'ابدأ الآن'
                                        : isFa
                                            ? 'شروع کنید'
                                            : 'Get Started')
                                : (isTr
                                    ? 'İleri'
                                    : isAr
                                        ? 'التالي'
                                        : isFa
                                            ? 'بعدی'
                                            : 'Next'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialSlideData {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _TutorialSlideData({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });
}
