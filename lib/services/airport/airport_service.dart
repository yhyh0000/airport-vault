import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/http.dart';

import 'airport_models.dart';

class AirportAuthRequired implements Exception {
  const AirportAuthRequired(this.message);

  final String message;

  @override
  String toString() => message;
}

class AirportRequestFailed implements Exception {
  const AirportRequestFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Web-compatible adapters for the two initial airports.
///
/// iKun currently exposes an SSPanel-style server-rendered page and
/// `/user/checkin`. Pokemon uses the common V2Board/XBoard API shape. We keep
/// parsing tolerant because both sites change domains and theme markup often.
class AirportService {
  AirportService() {
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = FlClashHttpOverrides.handleFindProxy;
        return client;
      },
    );
  }

  final Dio _dio = Dio(
    BaseOptions(
      responseType: ResponseType.plain,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
      headers: const {
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            'Chrome/128.0.0.0 Mobile Safari/537.36 AirportVault/0.1',
      },
    ),
  );

  Future<AirportSnapshot> sync(AirportSession session) async {
    return switch (session.kind) {
      AirportKind.ikun => _syncIkun(session),
      AirportKind.pokemon => _syncPokemon(session),
    };
  }

  Future<AirportSnapshot> checkIn(AirportSession session) async {
    final response = session.kind == AirportKind.ikun
        ? await _request(
            session,
            '/user/checkin',
            method: 'POST',
            headers: const {'X-Requested-With': 'XMLHttpRequest'},
          )
        : await _pokemonCheckin(session);

    _throwIfAuth(response);
    final body = _jsonMap(response.data);
    final message = _message(body) ?? _plainMessage(response.data);
    final already = _containsCheckinMessage(message);
    final success = already ||
        body?['ret']?.toString() == '1' ||
        body?['success'] == true ||
        body?['status']?.toString() == 'success';
    if (!success) {
      throw AirportRequestFailed(message ?? '签到接口返回了未知结果');
    }
    final current = await sync(session);
    return current.copyWith(
      checkinDone: true,
      message: message ?? (already ? '今天已经签到' : '签到成功'),
      fetchedAt: DateTime.now(),
    );
  }

  Future<AirportSnapshot> _syncIkun(AirportSession session) async {
    final response = await _request(session, '/user');
    _throwIfAuth(response);
    final html = response.data?.toString() ?? '';
    if (_looksLikeLoginPage(html, response.realUri.toString())) {
      throw const AirportAuthRequired('iKun 登录状态已失效，请重新网页登录');
    }
    final userInfo = response.headers.value('subscription-userinfo');
    final traffic = _parseTraffic('$html\n${userInfo ?? ''}');
    return AirportSnapshot(
      kind: session.kind,
      baseUrl: session.baseUrl,
      accountLabel: _firstMatch(html, [
        RegExp(r'(?:邮箱|email)[^<:：]{0,12}[:：]?\s*([^<\s]+@[^<\s]+)', caseSensitive: false),
      ]),
      upload: traffic.upload,
      download: traffic.download,
      total: traffic.total,
      expireAt: _parseDate(html),
      subscriptionUrl: _findSubscriptionUrl(html, session.baseUrl),
      checkinDone: _containsCheckinMessage(_stripHtml(html)),
      message: _firstMatch(html, [
        RegExp(r'(?:签到|checkin)[^<]{0,100}', caseSensitive: false),
      ]),
      fetchedAt: DateTime.now(),
    );
  }

  Future<AirportSnapshot> _syncPokemon(AirportSession session) async {
    final infoResponse = await _request(session, '/api/v1/user/info');
    _throwIfAuth(infoResponse);
    final info = _jsonMap(infoResponse.data);
    if (info == null) {
      final htmlResponse = await _request(session, '/');
      _throwIfAuth(htmlResponse);
      return _syncHtmlFallback(session, htmlResponse.data?.toString() ?? '');
    }
    final data = _asMap(info['data']) ?? info;
    final traffic = _parseTrafficMap(data);
    final subscribeUrl = await _getPokemonSubscribeUrl(session);
    return AirportSnapshot(
      kind: session.kind,
      baseUrl: session.baseUrl,
      accountLabel: _stringValue(data, const ['email', 'username', 'name']),
      upload: traffic.upload,
      download: traffic.download,
      total: traffic.total,
      expireAt: _parseEpoch(_numberValue(data, const ['expired_at', 'expire_at', 'expire'])),
      subscriptionUrl: subscribeUrl,
      fetchedAt: DateTime.now(),
    );
  }

  Future<AirportSnapshot> _syncHtmlFallback(
    AirportSession session,
    String html,
  ) async {
    if (_looksLikeLoginPage(html, session.baseUrl)) {
      throw const AirportAuthRequired('宝可梦机场登录状态已失效，请重新网页登录');
    }
    final traffic = _parseTraffic(html);
    return AirportSnapshot(
      kind: session.kind,
      baseUrl: session.baseUrl,
      upload: traffic.upload,
      download: traffic.download,
      total: traffic.total,
      expireAt: _parseDate(html),
      subscriptionUrl: _findSubscriptionUrl(html, session.baseUrl),
      fetchedAt: DateTime.now(),
    );
  }

  Future<Response<dynamic>> _pokemonCheckin(AirportSession session) async {
    final api = await _request(
      session,
      '/api/v1/user/checkin',
      method: 'POST',
      headers: const {'X-Requested-With': 'XMLHttpRequest'},
    );
    if (api.statusCode != 404 && api.statusCode != 405) return api;
    return _request(
      session,
      '/user/checkin',
      method: 'POST',
      headers: const {'X-Requested-With': 'XMLHttpRequest'},
    );
  }

  Future<String?> _getPokemonSubscribeUrl(AirportSession session) async {
    final response = await _request(session, '/api/v1/user/getSubscribe');
    if (response.statusCode == 404 || response.statusCode == 405) return null;
    final json = _jsonMap(response.data);
    final data = _asMap(json?['data']) ?? json;
    final value = _stringValue(
      data,
      const ['subscribe_url', 'subscribeUrl', 'subscription_url', 'url'],
    );
    return value == null ? null : _absoluteUrl(value, session.baseUrl);
  }

  Future<Response<dynamic>> _request(
    AirportSession session,
    String path, {
    String method = 'GET',
    Map<String, String>? headers,
  }) async {
    final base = session.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final url = path.startsWith('http') ? path : '$base$path';
    final requestHeaders = <String, String>{
      'Referer': '$base/',
      'Origin': base,
      if (session.cookie.trim().isNotEmpty) 'Cookie': session.cookie,
      if (session.accessToken != null) 'Authorization': 'Bearer ${session.accessToken}',
      ...?headers,
    };
    try {
      return await _dio.request<dynamic>(
        url,
        data: method == 'GET' ? null : <String, String>{},
        options: Options(method: method, headers: requestHeaders),
      );
    } on DioException catch (error) {
      throw AirportRequestFailed(
        error.response?.statusMessage ?? error.message ?? '机场网页暂时无法访问',
      );
    }
  }

  void _throwIfAuth(Response<dynamic> response) {
    final url = response.realUri.toString();
    final body = response.data?.toString() ?? '';
    if (response.statusCode == 401 ||
        response.statusCode == 419 ||
        _looksLikeLoginPage(body, url)) {
      throw const AirportAuthRequired('登录状态已失效，请重新网页登录');
    }
    if ((response.statusCode ?? 500) >= 400) {
      throw AirportRequestFailed('机场网页返回 HTTP ${response.statusCode}');
    }
  }

  bool _looksLikeLoginPage(String body, String url) {
    final lower = '$url\n$body'.toLowerCase();
    return lower.contains('/auth/login') ||
        lower.contains('#/login') ||
        (lower.contains('登录') && lower.contains('密码') && !lower.contains('签到成功'));
  }

  Map<String, dynamic>? _jsonMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is! String || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _asMap(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  String? _message(Map<String, dynamic>? json) {
    if (json == null) return null;
    for (final key in const ['msg', 'message', 'error', 'detail']) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    final data = _asMap(json['data']);
    return _message(data);
  }

  String? _plainMessage(Object? body) {
    if (body is! String) return null;
    final text = _stripHtml(body).trim();
    if (text.isEmpty) return null;
    return text.substring(0, text.length > 160 ? 160 : text.length);
  }

  bool _containsCheckinMessage(String? message) {
    if (message == null) return false;
    return RegExp(r'已签到|已经签到|今日已签|checked.?in|already', caseSensitive: false).hasMatch(message);
  }

  ({int upload, int download, int total}) _parseTraffic(String source) {
    final text = _stripHtml(source);
    return (
      upload: _bytesAfter(text, const ['upload', '上传']),
      download: _bytesAfter(text, const ['download', '下载']),
      total: _bytesAfter(text, const ['total', '总流量', '套餐流量', 'transfer_enable']),
    );
  }

  ({int upload, int download, int total}) _parseTrafficMap(
    Map<String, dynamic> data,
  ) {
    return (
      upload: _numberValue(data, const ['u', 'upload', 'upload_bytes']),
      download: _numberValue(data, const ['d', 'download', 'download_bytes']),
      total: _numberValue(data, const ['transfer_enable', 'total', 'traffic']),
    );
  }

  int _bytesAfter(String text, List<String> labels) {
    for (final label in labels) {
      final match = RegExp(
        '${RegExp.escape(label)}[^0-9]{0,100}(\\d+(?:\\.\\d+)?)\\s*(TB|GB|MB|KB|B)?',
        caseSensitive: false,
      ).firstMatch(text);
      if (match == null) continue;
      final number = double.tryParse(match.group(1) ?? '');
      if (number == null) continue;
      return _toBytes(number, match.group(2));
    }
    return 0;
  }

  int _numberValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final raw = data[key];
      final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (value != null) return value.round();
    }
    return 0;
  }

  String? _stringValue(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return null;
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') return value;
    }
    return null;
  }

  int _toBytes(double value, String? unit) {
    final multiplier = switch (unit?.toUpperCase()) {
      'TB' => 1024 * 1024 * 1024 * 1024,
      'GB' => 1024 * 1024 * 1024,
      'MB' => 1024 * 1024,
      'KB' => 1024,
      _ => 1,
    };
    return (value * multiplier).round();
  }

  DateTime? _parseEpoch(int value) {
    if (value <= 0) return null;
    final millis = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  DateTime? _parseDate(String source) {
    final hit = RegExp(
      r'(?:到期|expire|expired_at)[^0-9]{0,40}(\d{10,13}|20\d{2}[-/]\d{1,2}[-/]\d{1,2})',
      caseSensitive: false,
    ).firstMatch(source);
    if (hit == null) return null;
    final value = hit.group(1)!;
    final epoch = int.tryParse(value);
    if (epoch != null) return _parseEpoch(epoch);
    return DateTime.tryParse(value.replaceAll('/', '-'));
  }

  String? _firstMatch(String source, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(source);
      final value = match?.groupCount == 0 ? match?.group(0) : match?.group(1);
      if (value != null && value.trim().isNotEmpty) return _stripHtml(value).trim();
    }
    return null;
  }

  String? _findSubscriptionUrl(String html, String baseUrl) {
    final patterns = [
      RegExp(r'''href=["']([^"']+)["'][^>]{0,240}(?:订阅|subscription|clash|sing-box)''', caseSensitive: false),
      RegExp(r'''(?:订阅地址|订阅链接|subscription)[^a-z0-9]{0,40}(https?://[^\s"'<>]+)''', caseSensitive: false),
    ];
    final value = _firstMatch(html, patterns);
    return value == null ? null : _absoluteUrl(value, baseUrl);
  }

  String _absoluteUrl(String value, String baseUrl) {
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    final base = Uri.parse(baseUrl);
    return base.resolve(value).toString();
  }

  String _stripHtml(String value) {
    return value
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
