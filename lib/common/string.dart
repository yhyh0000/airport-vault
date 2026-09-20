import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/common.dart';

/// Normalizes a profile/subscription URL before it reaches Dio.
///
/// Airport panels sometimes expose `/link/...`, `//host/link/...`, or an
/// HTML-escaped URL instead of a fully-qualified URL. Dio accepts the string
/// type but fails later with the much less useful "No host specified" error.
String? normalizeProfileSourceUrl(
  String value, {
  String? baseUrl,
}) {
  var candidate = value
      .trim()
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'[\r\n\t]'), '');
  if (candidate.isEmpty) return null;

  final candidates = <String>[candidate];
  try {
    final decoded = Uri.decodeFull(candidate);
    if (decoded != candidate) candidates.add(decoded);
  } catch (_) {}

  final base = baseUrl == null ? null : Uri.tryParse(baseUrl.trim());
  for (final raw in candidates) {
    candidate = raw;
    if (candidate.startsWith('//')) candidate = 'https:$candidate';
    if (candidate.startsWith('www.')) candidate = 'https://$candidate';

    final direct = Uri.tryParse(candidate);
    if (_isHttpUri(direct)) return direct!.toString();

    if (base != null && _isHttpUri(base) && !candidate.contains('://')) {
      final resolved = base.resolve(candidate);
      if (_isHttpUri(resolved)) return resolved.toString();
    }
  }
  return null;
}

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
