import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:pve_manager/data/models/github_release.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();

class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
    TargetPlatform? platform,
    bool? isWeb,
  }) : _client = client ?? http.Client(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb;

  static final AppUpdateService instance = AppUpdateService();

  static const repositoryOwner = 'Canary233';
  static const repositoryName = 'pve_manager';
  static const _requestTimeout = Duration(seconds: 15);

  final http.Client _client;
  final PackageInfoLoader _packageInfoLoader;
  final TargetPlatform _platform;
  final bool _isWeb;

  Uri get latestReleaseUri => Uri.https(
    'api.github.com',
    '/repos/$repositoryOwner/$repositoryName/releases/latest',
  );

  Future<String> currentVersion() async {
    final packageInfo = await _packageInfoLoader();
    final version = packageInfo.version.trim();
    ReleaseVersion.parse(version);
    return version;
  }

  Future<AppUpdateInfo> checkForUpdate() async {
    final packageInfo = await _packageInfoLoader();
    final currentVersion = ReleaseVersion.parse(packageInfo.version);
    final release = await fetchLatestRelease();
    final latestVersion = ReleaseVersion.parse(release.tagName);

    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      release: release,
      asset: _selectAsset(release),
    );
  }

  Future<GitHubRelease> fetchLatestRelease() async {
    if (_isWeb ||
        (_platform != TargetPlatform.android &&
            _platform != TargetPlatform.windows)) {
      throw const AppUpdateException(
        'App updates are not supported on this platform.',
        unsupportedPlatform: true,
      );
    }

    late final http.Response response;
    try {
      response = await _client
          .get(
            latestReleaseUri,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'pve-manager',
            },
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const AppUpdateException('GitHub release request timed out.');
    } on http.ClientException catch (error) {
      throw AppUpdateException('GitHub release request failed: $error');
    }

    if (response.statusCode != 200) {
      throw AppUpdateException(
        'GitHub release request returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'GitHub release response is not an object.',
        );
      }
      return GitHubRelease.fromJson(decoded);
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('GitHub release response is invalid: $error');
    }
  }

  GitHubReleaseAsset? _selectAsset(GitHubRelease release) {
    if (_isWeb) {
      return null;
    }

    final suffixes = switch (_platform) {
      TargetPlatform.android => const [
        '-android-armv8.apk',
        '-android-armv7.apk',
      ],
      TargetPlatform.windows => const ['-windows-x64.zip'],
      _ => const <String>[],
    };

    for (final suffix in suffixes) {
      for (final asset in release.assets) {
        if (asset.name.toLowerCase().endsWith(suffix)) {
          return asset;
        }
      }
    }
    return null;
  }
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.release,
    required this.asset,
  });

  final ReleaseVersion currentVersion;
  final ReleaseVersion latestVersion;
  final GitHubRelease release;
  final GitHubReleaseAsset? asset;

  bool get hasUpdate => latestVersion.compareTo(currentVersion) > 0;

  bool get hasDirectDownload => asset != null;

  Uri get downloadUri =>
      Uri.parse(asset?.browserDownloadUrl ?? release.htmlUrl);
}

class AppUpdateException implements Exception {
  const AppUpdateException(
    this.message, {
    this.statusCode,
    this.unsupportedPlatform = false,
  });

  final String message;
  final int? statusCode;
  final bool unsupportedPlatform;

  @override
  String toString() => message;
}

class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.prerelease = const <String>[],
  });

  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;

  factory ReleaseVersion.parse(String value) {
    var normalized = value.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }
    if (normalized.isEmpty) {
      throw const FormatException('Version is empty.');
    }

    final withoutBuild = normalized.split('+').first;
    final separatorIndex = withoutBuild.indexOf('-');
    final coreText = separatorIndex == -1
        ? withoutBuild
        : withoutBuild.substring(0, separatorIndex);
    final prereleaseText = separatorIndex == -1
        ? null
        : withoutBuild.substring(separatorIndex + 1);
    final core = coreText.split('.');
    if (core.length != 3 ||
        core.any((part) => !RegExp(r'^\d+$').hasMatch(part))) {
      throw FormatException('Invalid version: $value');
    }

    final prerelease = prereleaseText != null
        ? prereleaseText.split('.')
        : const <String>[];
    if (prerelease.any(
      (part) => part.isEmpty || !RegExp(r'^[0-9A-Za-z-]+$').hasMatch(part),
    )) {
      throw FormatException('Invalid version: $value');
    }

    return ReleaseVersion(
      major: int.parse(core[0]),
      minor: int.parse(core[1]),
      patch: int.parse(core[2]),
      prerelease: List.unmodifiable(prerelease),
    );
  }

  @override
  int compareTo(ReleaseVersion other) {
    final coreComparison = _compareCore(other);
    if (coreComparison != 0) {
      return coreComparison;
    }
    if (prerelease.isEmpty && other.prerelease.isEmpty) {
      return 0;
    }
    if (prerelease.isEmpty) {
      return 1;
    }
    if (other.prerelease.isEmpty) {
      return -1;
    }

    final length = prerelease.length < other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var index = 0; index < length; index++) {
      final left = prerelease[index];
      final right = other.prerelease[index];
      if (left == right) {
        continue;
      }
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      if (leftNumber != null) {
        return -1;
      }
      if (rightNumber != null) {
        return 1;
      }
      return left.compareTo(right);
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }

  int _compareCore(ReleaseVersion other) {
    final majorComparison = major.compareTo(other.major);
    if (majorComparison != 0) {
      return majorComparison;
    }
    final minorComparison = minor.compareTo(other.minor);
    if (minorComparison != 0) {
      return minorComparison;
    }
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) {
    return other is ReleaseVersion && compareTo(other) == 0;
  }

  @override
  int get hashCode =>
      Object.hashAll(<Object?>[major, minor, patch, ...prerelease]);

  @override
  String toString() {
    final core = '$major.$minor.$patch';
    return prerelease.isEmpty ? core : '$core-${prerelease.join('.')}';
  }
}
