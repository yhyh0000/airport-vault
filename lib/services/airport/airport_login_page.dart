import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fl_clash/services/airport/airport_models.dart';
import 'package:fl_clash/widgets/surge/surge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  static const MethodChannel _nativeWebViewChannel =
      MethodChannel('airport_vault/webview');

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
            unawaited(_configureNativeWebView());
            unawaited(_applyWebTheme());
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
      ;
    unawaited(_initializeWebView());
  }

  Future<void> _initializeWebView() async {
    await _configureNativeWebView();
    if (!mounted) return;
    await _controller.loadRequest(Uri.parse(widget.site.loginUrl(widget.baseUrl)));
  }

  Future<void> _configureNativeWebView() async {
    try {
      await _nativeWebViewChannel.invokeMethod<void>('enableWebViewCookies');
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _nativeWebViewChannel.invokeMethod<void>('configureChromeWebView');
      }
    } catch (_) {
      // The Flutter WebView cookie manager remains as a fallback.
    }
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
      final currentUrl = await _currentUrl();
      final cookieValue = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final storageValue = await _controller.runJavaScriptReturningResult(
        'JSON.stringify(Object.fromEntries(Object.entries(localStorage)))',
      );
      final documentCookie = _decodeJsString(cookieValue);
      final cookie = await _readCookies(documentCookie, currentUrl);
      final storage = _decodeJsString(storageValue);
      final hasToken = _hasStorageToken(storage);
      if (cookie.trim().isEmpty && !hasToken) return null;
      return AirportSession(
        kind: widget.site.kind,
        baseUrl: _originOf(currentUrl) ?? widget.baseUrl,
        cookie: cookie,
        localStorageJson: storage.isEmpty ? '{}' : storage,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _readCookies(String documentCookie, String currentUrl) async {
    final values = <String, String>{};
    void collect(String raw) {
      for (final part in raw.split(';')) {
        final separator = part.indexOf('=');
        if (separator <= 0) continue;
        final name = part.substring(0, separator).trim();
        final value = part.substring(separator + 1).trim();
        if (name.isNotEmpty) values[name] = value;
      }
    }

    collect(documentCookie);
    final urls = <String>{
      currentUrl,
      widget.baseUrl,
      '${widget.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/',
      '${widget.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/user',
      '${widget.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/auth/login',
    }..removeWhere((url) => url.trim().isEmpty);
    for (final url in urls) {
      try {
        final native = await _nativeWebViewChannel.invokeMethod<String>(
          'getCookies',
          {'url': url},
        );
        collect(native ?? '');
      } catch (_) {}
      try {
        final cookies = await _cookieManager.getCookies(domain: Uri.parse(url));
        for (final item in cookies) {
          values[item.name] = item.value;
        }
      } catch (_) {}
    }
    return values.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  String? _originOf(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return null;
    return uri.hasPort
        ? '${uri.scheme}://${uri.host}:${uri.port}'
        : '${uri.scheme}://${uri.host}';
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

  Future<void> _applyWebTheme() async {
    try {
      final css = _webThemeCss(_accentColor);
      await _controller.runJavaScript('''
        (() => {
          const styleId = 'airport-vault-native-theme';
          let style = document.getElementById(styleId);
          if (!style) {
            style = document.createElement('style');
            style.id = styleId;
            document.head.appendChild(style);
          }
          style.textContent = ${jsonEncode(css)};
        })();
      ''');
    } catch (_) {
      // The native shell remains usable when a site blocks injected CSS.
    }
  }

  Color get _accentColor => widget.site.kind == AirportKind.pokemon
      ? const Color(0xFF2CC7C9)
      : const Color(0xFF5B61FF);

  String _webThemeCss(Color accent) {
    final accentHex = accent.value.toRadixString(16).substring(2);
    return '''
      :root { color-scheme: light; }
      html, body {
        background: #F6F7FB !important;
        color: #202124 !important;
      }
      body {
        margin: 0 !important;
        padding: 12px 10px 22px !important;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif !important;
      }
      a { color: #$accentHex !important; }
      input, textarea, select {
        min-height: 44px !important;
        border-radius: 12px !important;
        border: 1px solid #D9DCE5 !important;
        background: #FFFFFF !important;
        color: #202124 !important;
        box-sizing: border-box !important;
      }
      button, [role="button"], input[type="submit"] {
        min-height: 44px !important;
        border-radius: 12px !important;
        border: 0 !important;
        background: #$accentHex !important;
        color: #FFFFFF !important;
        box-shadow: none !important;
      }
      img { max-width: 100% !important; border-radius: 16px !important; }
      .card, .panel, .box, .login, .login-card, .form-container,
      [class*="card"], [class*="panel"] {
        border-radius: 18px !important;
        box-shadow: 0 6px 20px rgba(32, 33, 36, 0.08) !important;
        border-color: #E4E7EF !important;
      }
      label, .form-label { color: #5C6375 !important; font-weight: 600 !important; }
      .text-muted, .help-block, small { color: #7B8292 !important; }
    ''';
  }

  Widget _buildBrandHero(BuildContext context) {
    final icon = widget.site.kind == AirportKind.pokemon
        ? Icons.catching_pokemon_rounded
        : Icons.bolt_rounded;
    final secondary = Color.lerp(_accentColor, Colors.black, 0.28)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_accentColor, secondary],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: _accentColor.withValues(alpha: 0.24),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -34,
              top: -46,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 22,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Icon(icon, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '登录到机场钥仓',
                              style: context.typography.cardTitle.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '统一管理你的机场账户与订阅',
                              style: context.typography.compactDescription
                                  .copyWith(
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.verified_user_rounded,
                        color: Colors.white.withValues(alpha: 0.86),
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildHeroPill(
                        context: context,
                        icon: Icons.cloud_rounded,
                        label: widget.site.title,
                      ),
                      _buildHeroPill(
                        context: context,
                        icon: Icons.sync_rounded,
                        label: '同步流量与签到',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroPill({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.88), size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: context.typography.badgeLabel.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildWebViewSurface(BuildContext context, SurgeTheme surge) {
    return SurgeCard(
      padding: EdgeInsets.zero,
      shadow: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.lock_rounded,
                    color: _accentColor,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '安全登录',
                        style: context.typography.cardTitle.copyWith(
                          color: surge.textPrimary,
                        ),
                      ),
                      Text(
                        '登录信息仅用于绑定当前机场账户',
                        style: context.typography.compactDescription.copyWith(
                          color: surge.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_pageLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accentColor,
                    ),
                  )
                else
                  Icon(
                    Icons.check_circle_rounded,
                    color: _accentColor,
                    size: 18,
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: surge.separator),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_webError!}\n请返回重试自动探测，或稍后再试。',
                style: context.typography.body.copyWith(
                  color: colorScheme.onErrorContainer,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final surge = SurgeTheme.of(context);
    return Scaffold(
      backgroundColor: surge.background,
      appBar: AppBar(
        backgroundColor: surge.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          '账户绑定',
          style: context.typography.sectionTitle.copyWith(
            color: surge.textPrimary,
          ),
        ),
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
          _buildBrandHero(context),
          if (_webError != null) _buildError(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _buildWebViewSurface(context, surge),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SurgeCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                shadow: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            _finishing
                                ? Icons.sync_rounded
                                : Icons.verified_user_outlined,
                            size: 18,
                            color: _accentColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.typography.compactDescription
                                  .copyWith(color: surge.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                      ),
                      onPressed: _finishing ? null : _finish,
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: Text(_finishing ? '绑定中…' : '完成绑定'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
