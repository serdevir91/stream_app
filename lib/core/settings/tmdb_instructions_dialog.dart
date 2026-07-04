import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../i18n/app_text.dart';

void showTmdbTokenInstructions(BuildContext context, AppText text) {
  showDialog(
    context: context,
    builder: (context) {
      final isTr = text.languageCode == 'tr';
      return AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Text(
              isTr ? 'TMDB Token Nasıl Alınır?' : 'How to Get TMDB Token?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStep(
                '1',
                isTr
                    ? 'themoviedb.org sitesine kaydolun veya giriş yapın.'
                    : 'Sign up or log in to themoviedb.org.',
              ),
              _buildStep(
                '2',
                isTr
                    ? 'Profil simgenize tıklayıp Settings (Ayarlar) -> API sayfasına gidin.'
                    : 'Click your profile icon and go to Settings -> API.',
              ),
              _buildStep(
                '3',
                isTr
                    ? 'Create (Oluştur) butonuna tıklayıp Developer (Geliştirici) seçeneğini seçin.'
                    : 'Click the Create button and select Developer.',
              ),
              _buildStep(
                '4',
                isTr
                    ? 'Formu doldurun (Örn: Stream App, Kişisel kullanım).'
                    : 'Fill in the form (e.g. Stream App, Personal use).',
              ),
              _buildStep(
                '5',
                isTr
                    ? 'Sayfanın altındaki uzun "API Read Access Token" (API Okuma Erişim Belirteci) değerini kopyalayın (Kısa olan API Key\'i değil).'
                    : 'Copy the long "API Read Access Token" at the bottom of the page (NOT the short API Key).',
              ),
              _buildStep(
                '6',
                isTr
                    ? 'Kopyaladığınız uzun tokenı uygulamaya yapıştırıp kaydedin.'
                    : 'Paste the long token into the app and save.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              isTr ? 'Kapat' : 'Close',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final Uri url = Uri.parse(
                'https://www.themoviedb.org/settings/api',
              );
              try {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(
              isTr ? 'TMDB API Sayfasına Git' : 'Go to TMDB API Page',
            ),
          ),
        ],
      );
    },
  );
}

Widget _buildStep(String stepNumber, String instruction) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: Colors.orangeAccent,
          child: Text(
            stepNumber,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            instruction,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}
