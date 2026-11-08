import 'package:flutter_test/flutter_test.dart';
import 'package:stream_app/core/updater/app_updater_service.dart';

void main() {
  final assets = [
    {'name': 'app-arm64-v8a-release.apk'},
    {'name': 'app-armeabi-v7a-release.apk'},
    {'name': 'app-release.apk'},
    {'name': 'app-x86_64-release.apk'},
    {'name': 'StreamApp-Setup.exe'},
  ];

  test('picks the split APK for the device ABI', () {
    expect(AppUpdaterService.pickApkAsset(assets, ['x86_64'])['name'], 'app-x86_64-release.apk');
    expect(
      AppUpdaterService.pickApkAsset(assets, ['arm64-v8a', 'armeabi-v7a'])['name'],
      'app-arm64-v8a-release.apk',
    );
  });

  test('falls back to the universal APK', () {
    expect(AppUpdaterService.pickApkAsset(assets, const [])['name'], 'app-release.apk');
    expect(AppUpdaterService.pickApkAsset(assets, ['mips'])['name'], 'app-release.apk');
  });

  test('no APK gives null', () {
    expect(AppUpdaterService.pickApkAsset([{'name': 'a.exe'}], ['x86_64']), isNull);
  });
}
