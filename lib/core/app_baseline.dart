import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'i18n/app_text.dart';
import 'settings/app_settings_provider.dart';
import 'updater/app_updater_service.dart';

/// Update check, review prompt and support link for the GitHub build.
class AppBaseline {
  AppBaseline._();

  static const String repoUrl = 'https://github.com/serdevir91/stream_app';

  /// Donation page. The Support entry stays hidden while this is empty.
  static const String donationUrl = '';

  static const int _completionsBeforeReview = 5;

  static bool _reviewPending = false;
  static bool _updateChecked = false;

  static Future<void> openRepo() async {
    await launchUrl(Uri.parse(repoUrl), mode: LaunchMode.externalApplication);
  }

  static Future<void> openDonation() async {
    if (donationUrl.isEmpty) return;
    await launchUrl(Uri.parse(donationUrl), mode: LaunchMode.externalApplication);
  }

  /// Counts one finished movie or episode. After the fifth, the review
  /// prompt shows the next time the player closes.
  static Future<void> recordCompletion(WidgetRef ref) async {
    final notifier = ref.read(appSettingsProvider.notifier);
    final settings = ref.read(appSettingsProvider);
    final plays = settings.completedPlays + 1;
    await notifier.patch((s) => s.copyWith(completedPlays: plays));
    if (plays >= _completionsBeforeReview && !settings.reviewPromptShown) {
      _reviewPending = true;
    }
  }

  static Future<void> _showReviewPrompt(NavigatorState navigator) async {
    if (!_reviewPending || !navigator.mounted) return;
    _reviewPending = false;
    final context = navigator.context;
    final container = ProviderScope.containerOf(context, listen: false);
    final text = container.read(appTextProvider);
    await container
        .read(appSettingsProvider.notifier)
        .patch((s) => s.copyWith(reviewPromptShown: true));
    if (!navigator.mounted) return;
    final star = await showDialog<bool>(
      context: navigator.context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.star_rounded, color: Colors.amber, size: 40),
        title: Text(text.t('review_prompt_title')),
        content: Text(text.t('review_prompt_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.t('later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.t('star_on_github')),
          ),
        ],
      ),
    );
    if (star == true) await openRepo();
  }

  /// Looks for a newer GitHub release once per launch and offers it.
  static Future<void> checkForUpdatesSilently(BuildContext context) async {
    if (_updateChecked) return;
    _updateChecked = true;
    await Future<void>.delayed(const Duration(seconds: 4));
    final service = AppUpdaterService();
    final info = await service.checkForUpdate();
    if (info == null || !context.mounted) return;
    final text = ProviderScope.containerOf(context, listen: false).read(appTextProvider);
    final notes = info.releaseNotes.trim();
    final update = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update_rounded, size: 36),
        title: Text('${text.t('new_update_found')}: ${info.latestVersion}'),
        content: notes.isEmpty
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Text(notes.length > 1200 ? '${notes.substring(0, 1200)}…' : notes),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.t('later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.t('update_now')),
          ),
        ],
      ),
    );
    if (update != true || !context.mounted) return;

    final progress = ValueNotifier<double>(0);
    final done = Completer<String?>();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          done.future.then((_) {
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          });
          return AlertDialog(
            title: Text(text.t('downloading_update')),
            content: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, value, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: value > 0 ? value : null),
                  const SizedBox(height: 10),
                  Text('${(value * 100).round()}%'),
                ],
              ),
            ),
          );
        },
      ),
    );
    await service.performUpdate(
      info,
      onProgress: (p) => progress.value = p,
      onComplete: () {
        if (!done.isCompleted) done.complete(null);
      },
      onError: (err) {
        if (!done.isCompleted) done.complete(err);
      },
    );
    final error = await done.future;
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${text.t('error_prefix')}: $error')),
      );
    }
  }
}

/// Shows the pending review prompt once the player route closes.
class BaselineNavigatorObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!AppBaseline._reviewPending || route is! PageRoute) return;
    final nav = navigator;
    if (nav == null) return;
    Future<void>.delayed(
      const Duration(milliseconds: 700),
      () => AppBaseline._showReviewPrompt(nav),
    );
  }
}
