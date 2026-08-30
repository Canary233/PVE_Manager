import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:pve_manager/data/services/app_update_service.dart';

void main() {
  PackageInfo packageInfo(String version) {
    return PackageInfo(
      appName: 'PVE Manager',
      packageName: 'com.canary233.PVEManager',
      version: version,
      buildNumber: '1',
    );
  }

  Map<String, Object> releaseJson({
    String tagName = 'v1.2.0',
    List<Map<String, Object>>? assets,
  }) {
    return {
      'tag_name': tagName,
      'name': 'PVE Manager $tagName',
      'body': 'Bug fixes',
      'html_url':
          'https://github.com/Canary233/pve_manager/releases/tag/$tagName',
      'published_at': '2026-08-30T00:00:00Z',
      'assets':
          assets ??
          [
            {
              'name': 'pve-manager-$tagName-android-armv8.apk',
              'browser_download_url':
                  'https://github.com/Canary233/pve_manager/releases/download/$tagName/pve-manager-$tagName-android-armv8.apk',
              'size': 123,
            },
            {
              'name': 'pve-manager-$tagName-windows-x64.zip',
              'browser_download_url':
                  'https://github.com/Canary233/pve_manager/releases/download/$tagName/pve-manager-$tagName-windows-x64.zip',
              'size': 456,
            },
          ],
    };
  }

  test('compares release versions and selects the Android asset', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/repos/Canary233/pve_manager/releases/latest');
      expect(request.headers['user-agent'], 'pve-manager');
      return http.Response(jsonEncode(releaseJson()), 200);
    });
    final service = AppUpdateService(
      client: client,
      platform: TargetPlatform.android,
      packageInfoLoader: () async => packageInfo('1.1.9'),
      isWeb: false,
    );

    final update = await service.checkForUpdate();

    expect(update.hasUpdate, isTrue);
    expect(update.currentVersion.toString(), '1.1.9');
    expect(update.latestVersion.toString(), '1.2.0');
    expect(update.asset?.name, endsWith('-android-armv8.apk'));
    expect(update.hasDirectDownload, isTrue);
  });

  test(
    'selects the Windows asset and reports no update when versions match',
    () async {
      final service = AppUpdateService(
        client: MockClient(
          (_) async => http.Response(jsonEncode(releaseJson()), 200),
        ),
        platform: TargetPlatform.windows,
        packageInfoLoader: () async => packageInfo('1.2.0+9'),
        isWeb: false,
      );

      final update = await service.checkForUpdate();

      expect(update.hasUpdate, isFalse);
      expect(update.asset?.name, endsWith('-windows-x64.zip'));
    },
  );

  test('follows semantic version prerelease ordering', () {
    expect(
      ReleaseVersion.parse(
        'v1.0.0',
      ).compareTo(ReleaseVersion.parse('1.0.0-rc.1')),
      greaterThan(0),
    );
    expect(
      ReleaseVersion.parse(
        '1.0.0-rc.2',
      ).compareTo(ReleaseVersion.parse('1.0.0-rc.10')),
      lessThan(0),
    );
    expect(
      ReleaseVersion.parse('1.0.0+build.2'),
      ReleaseVersion.parse('1.0.0'),
    );
  });

  test('rejects an invalid release response', () async {
    final service = AppUpdateService(
      client: MockClient((_) async => http.Response('{"tag_name":"bad"}', 200)),
      platform: TargetPlatform.android,
      packageInfoLoader: () async => packageInfo('1.0.0'),
      isWeb: false,
    );

    expect(service.checkForUpdate(), throwsA(isA<FormatException>()));
  });

  test('preserves the GitHub status when no release exists', () async {
    final service = AppUpdateService(
      client: MockClient((_) async => http.Response('{}', 404)),
      platform: TargetPlatform.android,
      packageInfoLoader: () async => packageInfo('1.0.0'),
      isWeb: false,
    );

    expect(
      service.checkForUpdate(),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });

  test('rejects unsupported platforms before making a request', () async {
    var requestCount = 0;
    final service = AppUpdateService(
      client: MockClient((_) async {
        requestCount++;
        return http.Response('{}', 200);
      }),
      platform: TargetPlatform.iOS,
      packageInfoLoader: () async => packageInfo('1.0.0'),
      isWeb: false,
    );

    expect(
      service.checkForUpdate(),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.unsupportedPlatform,
          'unsupportedPlatform',
          isTrue,
        ),
      ),
    );
    expect(requestCount, 0);
  });
}
