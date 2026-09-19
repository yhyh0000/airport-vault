import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'airport_models.dart';

/// Logs in through the airport's own web page so Geetest/Turnstile and other
/// site-specific challenges stay in the official flow. The app only reads the
/// resulting same-site cookie/localStorage after the user taps “完成登录”.
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
  String? _lastUrl;

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
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _pageLoading = false;
              _lastUrl = url;
            });
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('网页加载失败：${error.description}')),
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.site.loginUrl(widget.baseUrl)));
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
        const SnackBar(content: Text('还没有读取到登录会话，请先完成网页登录')),
      );
      return;
    }
    Navigator.of(context).pop(session);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.site.title}网页登录'),
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
          Expanded(child: WebViewWidget(controller: _controller)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _lastUrl ?? widget.baseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _finish,
                    icon: const Icon(Icons.lock_open_rounded, size: 18),
                    label: const Text('完成登录'),
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
