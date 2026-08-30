class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
  });

  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<GitHubReleaseAsset> assets;

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    final tagName = _requiredString(json, 'tag_name');
    final rawAssets = json['assets'];
    if (rawAssets is! List) {
      throw const FormatException('GitHub release assets are invalid.');
    }

    final publishedAtValue = json['published_at'];
    DateTime? publishedAt;
    if (publishedAtValue is String && publishedAtValue.isNotEmpty) {
      publishedAt = DateTime.tryParse(publishedAtValue);
    }

    return GitHubRelease(
      tagName: tagName,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : tagName,
      body: (json['body'] as String?) ?? '',
      htmlUrl: _requiredString(json, 'html_url'),
      publishedAt: publishedAt,
      assets: [
        for (final item in rawAssets)
          if (item is Map<String, dynamic>) GitHubReleaseAsset.fromJson(item),
      ],
    );
  }
}

class GitHubReleaseAsset {
  const GitHubReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.size,
  });

  final String name;
  final String browserDownloadUrl;
  final int size;

  factory GitHubReleaseAsset.fromJson(Map<String, dynamic> json) {
    final sizeValue = json['size'];
    return GitHubReleaseAsset(
      name: _requiredString(json, 'name'),
      browserDownloadUrl: _requiredString(json, 'browser_download_url'),
      size: sizeValue is int ? sizeValue : 0,
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw FormatException('GitHub release field "$key" is missing.');
}
