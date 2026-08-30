import 'package:pve_manager/core/utils/formatters.dart';

class PveStorageDetail {
  const PveStorageDetail({
    required this.node,
    required this.status,
    this.config,
  });

  final String node;
  final PveStorageStatus status;
  final PveStorageConfig? config;

  String get storage => status.storage;

  String get type => config?.type ?? status.type;

  List<String> get contentTypes {
    final configured = config?.contentTypes ?? const <String>[];
    if (configured.isNotEmpty) {
      return configured;
    }
    return status.contentTypes;
  }
}

class PveStorageStatus {
  const PveStorageStatus({
    required this.storage,
    required this.type,
    required this.active,
    required this.enabled,
    required this.shared,
    required this.total,
    required this.used,
    required this.available,
    required this.usedFraction,
    this.contentTypes = const <String>[],
    this.path,
  });

  factory PveStorageStatus.fromJson(
    Map<String, dynamic> json, {
    required String fallbackStorage,
  }) {
    final total = asInt(json['total']);
    final used = asInt(json['used']);
    final available = asInt(json['avail'] ?? json['available']);
    final fraction = json['used_fraction'] is num
        ? asDouble(json['used_fraction'])
        : total > 0
        ? used / total
        : 0;

    return PveStorageStatus(
      storage: _string(json['storage'], fallbackStorage),
      type: _string(json['type'], '-'),
      active: _bool(json['active'], fallback: false),
      enabled: !_bool(json['disable'], fallback: false),
      shared: _bool(json['shared'], fallback: false),
      total: total,
      used: used,
      available: available,
      usedFraction: fraction.clamp(0, 1).toDouble(),
      contentTypes: _contentTypes(json['content']),
      path: _nullableString(json['path']),
    );
  }

  final String storage;
  final String type;
  final bool active;
  final bool enabled;
  final bool shared;
  final int total;
  final int used;
  final int available;
  final double usedFraction;
  final List<String> contentTypes;
  final String? path;
}

class PveStorageConfig {
  const PveStorageConfig({
    required this.storage,
    required this.type,
    required this.contentTypes,
    required this.shared,
    required this.enabled,
    this.path,
    this.nodes = const <String>[],
  });

  factory PveStorageConfig.fromJson(
    Map<String, dynamic> json, {
    required String fallbackStorage,
  }) {
    return PveStorageConfig(
      storage: _string(json['storage'], fallbackStorage),
      type: _string(json['type'], '-'),
      contentTypes: _contentTypes(json['content']),
      shared: _bool(json['shared'], fallback: false),
      enabled: !_bool(json['disable'], fallback: false),
      path: _nullableString(json['path']),
      nodes: _stringList(json['nodes']),
    );
  }

  final String storage;
  final String type;
  final List<String> contentTypes;
  final bool shared;
  final bool enabled;
  final String? path;
  final List<String> nodes;
}

class PveStorageContent {
  const PveStorageContent({
    required this.volumeId,
    required this.contentType,
    required this.format,
    required this.size,
    required this.used,
    this.vmid,
    this.createdAt,
    this.notes,
    this.parent,
    this.isBase = false,
  });

  factory PveStorageContent.fromJson(Map<String, dynamic> json) {
    final createdAt = asInt(json['ctime']);
    return PveStorageContent(
      volumeId: _string(json['volid'] ?? json['volume'], '-'),
      contentType: _string(json['content'], 'unknown'),
      format: _string(json['format'], '-'),
      size: asInt(json['size']),
      used: asInt(json['used']),
      vmid: asNullableInt(json['vmid']),
      createdAt: createdAt > 0 ? createdAt : null,
      notes: _nullableString(json['notes']),
      parent: _nullableString(json['parent']),
      isBase: _bool(json['is_base'], fallback: false),
    );
  }

  final String volumeId;
  final String contentType;
  final String format;
  final int size;
  final int used;
  final int? vmid;
  final int? createdAt;
  final String? notes;
  final String? parent;
  final bool isBase;
}

String _string(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _bool(Object? value, {required bool fallback}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
    return true;
  }
  if (normalized == '0' || normalized == 'false' || normalized == 'no') {
    return false;
  }
  return fallback;
}

List<String> _contentTypes(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (item.toString().trim().isNotEmpty) item.toString().trim(),
    ];
  }
  final text = value?.toString() ?? '';
  return text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (item.toString().trim().isNotEmpty) item.toString().trim(),
    ];
  }
  final text = value?.toString() ?? '';
  return text.isEmpty
      ? const <String>[]
      : text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
}
