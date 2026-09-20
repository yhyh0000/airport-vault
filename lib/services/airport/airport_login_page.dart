import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'airport_models.dart';

/// Logs in through the airport's own web page so Geetest/Turnstile and other
/// site-specific challenges stay in the official flow. The app only reads the
/// resulting same-site cookie/localStorage after the user completes login.
class AirportLoginPage extends StatefulWidget {
  const AirportLoginPage({
    required this.site,
    required this.baseUrl,
    super.key,
  });

  final AirportSiteDefinition site;
  final String baseUrl;

  @override
  State<AirportLoginPage> createState() => _AirportLoginPageState();
}

class _AirportLoginPageState extends State<AirportLoginPage> {
  late final WebViewController _controller;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  bool _pageLoading = true;
  bool _detectingSession = false;
  bool _finishing = false;
  String? _lastUrl;
  String? _webError;
  String _statusText = '登录成功后会自动返回账户中心';
  Timer? _sessionDetectionTimer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Theme.of(context).scaffoldBackgroundColor)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _pageLoading = true;
              _lastUrl = url;
              _webError = null;
              if (!_finishing) _statusText = '登录成功后会自动返回账户中心';
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _pageLoading = false;
              _lastUrl = url;
            });
            _scheduleSessionDetection();
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _pageLoading = false;
              _webError = '网页加载失败：${error.description}';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_webError!)),
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.site.loginUrl(widget.baseUrl)));
  }

  @override
  void dispose() {
    _sessionDetectionTimer?.cancel();
    super.dispose();
  }

  void _scheduleSessionDetection() {
    _sessionDetectionTimer?.cancel();
    var attempts = 0;
    _sessionDetectionTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (timer) async {
        attempts++;
        await _tryFinishAfterLogin();
        if (!mounted || _finishing || attempts >= 20) timer.cancel();
      },
    );
  }

  Future<void> _tryFinishAfterLogin() async {
    if (_detectingSession || _finishing || !mounted) return;
    _detectingSession = true;
    try {
      final url = await _currentUrl();
      if (_isLoginUrl(url)) return;
      final session = await _captureSession();
      if (session == null) return;
      final body = _decodeJsString(
        await _controller.runJavaScriptReturningResult(
          'document.body?.innerText ?? ""',
        ),
      ).toLowerCase();
      final authenticated = session.accessToken != null ||
          RegExp(
            r'签到|签入|订阅|流量|账户|退出|logout|dashboard',
            caseSensitive: false,
          ).hasMatch(body);
      if (authenticated) await _complete(session);
    } catch (_) {
      // Some SPAs do not expose their route immediately. The manual binding
      // button remains available as a safe fallback.
    } finally {
      _detectingSession = false;
    }
  }

  Future<String> _currentUrl() async {
    try {
      final value = await _controller.runJavaScriptReturningResult(
        'window.location.href',
      );
      final url = _decodeJsString(value).trim();
      if (url.isNotEmpty) return url;
    } catch (_) {}
    return _lastUrl ?? widget.baseUrl;
  }

  bool _isLoginUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/auth/login') ||
        lower.contains('#/login') ||
        lower.contains('/login');
  }

  Future<AirportSession?> _captureSession() async {
    try {
      final cookieValue = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final storageValue = await _controller.runJavaScriptReturningResult(
        'JSON.stringify(Object.fromEntries(Object.entries(localStorage)))',
      );
      final documentCookie = _decodeJsString(cookieValue);
      final cookie = await _readCookies(documentCookie);
      final storage = _decodeJsString(storageValue);
      final hasToken = _hasStorageToken(storage);
      if (cookie.trim().isEmpty && !hasToken) return null;
      return AirportSession(
        kind: widget.site.kind,
        baseUrl: widget.baseUrl,
        cookie: cookie,
        localStorageJson: storage.isEmpty ? '{}' : storage,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _readCookies(String documentCookie) async {
    final values = <String, String>{};
    for (final part in documentCookie.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      final value = part.substring(separator + 1).trim();
      if (name.isNotEmpty) values[name] = value;
    }
    try {
      final cookies = await _cookieManager.getCookies(
        domain: Uri.parse(widget.baseUrl),
      );
      for (final item in cookies) {
        values[item.name] = item.value;
      }
    } catch (_) {
      // document.cookie is still useful on older WebView implementations.
    }
    return values.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  String _decodeJsString(Object? value) {
    if (value is! String) return value?.toString() ?? '';
    try {
      final decoded = jsonDecode(value);
      return decoded is String ? decoded : jsonEncode(decoded);
    } catch (_) {
      return value;
    }
  }

  bool _hasStorageToken(String storage) {
    try {
      final decoded = jsonDecode(storage);
      if (decoded is! Map) return false;
      return const ['token', 'auth_token', 'access_token', 'accessToken']
          .any((key) => decoded[key]?.toString().trim().isNotEmpty == true);
    } catch (_) {
      return false;
    }
  }

  Future<void> _finish() async {
    final session = await _captureSession();
    if (!mounted) return;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有读取到登录会话，请先完成账户登录')),
      );
      return;
    }
    await _complete(session);
  }

  Future<void> _complete(AirportSession session) async {
    if (_finishing || !mounted) return;
    _finishing = true;
    _sessionDetectionTimer?.cancel();
    setState(() => _statusText = '登录成功，正在绑定账户…');
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    Navigator.of(context).pop(session);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('绑定${widget.site.title}账户'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_pageLoading) const LinearProgressIndicator(minHeight: 2),
          if (_webError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_webError!}\n请返回重试自动探测，或稍后再试。',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _controller.reload(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _finishing ? null : _finish,
                    icon: const Icon(Icons.lock_open_rounded, size: 18),
                    label: Text(_finishing ? '正在绑定…' : '手动绑定账户'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
