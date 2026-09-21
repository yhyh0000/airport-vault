import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/common.dart';

/// Parses a profile/subscription source into a URI that Dio can actually
/// request.
///
/// Airport panels do not all return the same representation. Depending on the
/// theme, the value may be a relative `/link/...`, a protocol-relative URL,
/// HTML/JavaScript escaped text (`https:\/\/...`), or a quoted/percent-encoded
/// value. Keeping this conversion in one place prevents a malformed value from
/// reaching Dio, where it otherwise becomes the opaque "No host specified"
/// exception shown in the import dialog.
Uri? parseProfileSourceUri(
  String value, {
  String? baseUrl,
}) {
  final candidates = <String>[];
  var candidate = value.trim();
  if (candidate.isEmpty) return null;

  void addCandidate(String input) {
    var normalized = input
        .trim()
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll(r'\/', '/')
        .replaceAll(r'\"', '"')
        .replaceAll(RegExp(r'[\r\n\t]'), '');
    while (normalized.length >= 2 &&
        ((normalized.startsWith('"') && normalized.endsWith('"')) ||
            (normalized.startsWith("'") && normalized.endsWith("'")))) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    if (normalized.isNotEmpty && !candidates.contains(normalized)) {
      candidates.add(normalized);
    }
  }

  addCandidate(candidate);
  try {
    final decoded = Uri.decodeFull(candidate);
    if (decoded != candidate) addCandidate(decoded);
  } catch (_) {}

  // A copied value can include a label such as `订阅地址：` before the actual
  // URL. Extract only an embedded web URL in that case; do not do this for
  // arbitrary text unless a real http(s) URL is present.
  final embedded = RegExp(r'(?:(?:https?:)?//)[^\s"<>]+').firstMatch(candidate);
  if (embedded != null) addCandidate(embedded.group(0)!);

  Uri? base;
  if (baseUrl != null) {
    base = Uri.tryParse(baseUrl.trim());
    if (!_isHttpUri(base)) base = null;
  }

  for (final raw in candidates) {
    var current = raw;
    if (current.startsWith('//')) current = 'https:$current';
    if (current.startsWith('www.')) current = 'https://$current';

    final direct = Uri.tryParse(current);
    if (_isHttpUri(direct)) return direct;

    if (base != null && !current.contains('://')) {
      final resolved = base.resolve(current);
      if (_isHttpUri(resolved)) return resolved;
    }
  }
  return null;
}

String? normalizeProfileSourceUrl(
  String value, {
  String? baseUrl,
}) =>
    parseProfileSourceUri(value, baseUrl: baseUrl)?.toString();

bool _isHttpUri(Uri? uri) {
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

final class InvalidProfileSourceUrl implements Exception {
  const InvalidProfileSourceUrl();

  @override
  String toString() => '订阅地址无效，请检查是否为完整的 http(s) 地址';
}

extension StringExtension on String {
  bool get isUrl {
    final uri = Uri.tryParse(this);
    return uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'ftp') &&
        uri.host.isNotEmpty;
  }

  dynamic get splitByMultipleSeparators {
    final parts = split(
      RegExp(r'[, ;]+'),
    ).where((part) => part.isNotEmpty).toList();

    return parts.length > 1 ? parts : this;
  }

  int compareToLower(String other) {
    return toLowerCase().compareTo(other.toLowerCase());
  }

  Uint8List? get getBase64 {
    final regExp = RegExp(r'base64,(.*)');
    final match = regExp.firstMatch(this);
    final realValue = match?.group(1) ?? '';
    if (realValue.isEmpty) {
      return null;
    }
    try {
      return base64.decode(realValue);
    } catch (e) {
      return null;
    }
  }

  bool get isSvg {
    return endsWith('.svg');
  }

  bool get isRegex {
    try {
      RegExp(this);
      return true;
    } catch (e) {
      commonPrint.log(e.toString());
      return false;
    }
  }

  String toMd5() {
    final bytes = utf8.encode(this);
    return md5.convert(bytes).toString();
  }

  // bool containsToLower(String target) {
  //   return toLowerCase().contains(target);
  // }

  Future<T> commonToJSON<T>() async {
    const thresholdLimit = 51200;
    if (length < thresholdLimit) {
      return json.decode(this);
    } else {
      return decodeJSONTask<T>(this);
    }
  }

  String? get value {
    if (isEmpty) {
      return null;
    }
    return this;
  }
}

extension StringNullExt on String? {
  String takeFirstValid(List<String?> others, {String defaultValue = ''}) {
    if (this != null && this!.trim().isNotEmpty) return this!.trim();

    for (final s in others) {
      if (s != null && s.trim().isNotEmpty) {
        return s.trim();
      }
    }
    return defaultValue;
  }
}
