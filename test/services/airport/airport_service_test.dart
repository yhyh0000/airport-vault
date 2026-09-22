import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/services/airport/airport_models.dart';
import 'package:fl_clash/services/airport/airport_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late String baseUrl;
  late String mode;
  final requests = <String, String>{};

  setUp(() async {
    mode = 'ikun';
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests['${request.method} ${request.uri.path}'] = body;

      if ((mode == 'ikun' || mode == 'ikun-current' || mode == 'ikun-log') &&
          request.uri.path == '/user') {
        if (mode == 'ikun-log') {
          await _write(
            request,
            _wrappedHtml('''
              <html><body>
                email: log@example.com
                <a href="/user/subscribe_log">订阅记录</a>
              </body></html>
            '''),
            ContentType.html,
          );
          return;
        }
        if (mode == 'ikun-current') {
          await _write(
            request,
            _wrappedHtml('''
              <html><body>
                <div class="traffic">今日已用<br><span class="counter">2</span> MB</div>
                <div class="traffic">剩余流量 <span class="counter">3</span> GB</div>
                <a data-clipboard-text="https:///link/invalid">无效地址</a>
                <button data-clipboard-text-encoded="aHR0cHM6Ly9zdWIuZXhhbXBsZS9saW5rL3NlY3JldC10b2tlbg==" data-clipboard-text-extra="&amp;extend=1">一键订阅</button>
              </body></html>
            '''),
            ContentType.html,
          );
          return;
        }
        request.response.headers.add(
          'subscription-userinfo',
          'upload=1048576; download=2097152; total=10485760; expire=1893456000',
        );
        await _write(
          request,
          _wrappedHtml('''
            <html><body>
              email: user@example.com
              <a href="/api/v1/client/subscribe?token=abc">订阅</a>
            </body></html>
          '''),
          ContentType.html,
        );
        return;
      }
      if (mode == 'ikun-log' && request.uri.path == '/user/subscribe_log') {
        await _write(
          request,
          _wrappedHtml('''
            <html><body>
              <a href="/user/subscribe_log">订阅记录</a>
              <button data-clipboard-text="/link/log-token">复制订阅地址</button>
            </body></html>
          '''),
          ContentType.html,
        );
        return;
      }
      if (mode == 'ikun' && request.uri.path == '/user/checkin') {
        await _write(
          request,
          jsonEncode({'ret': 1, 'msg': '获得了 100 MB 流量'}),
          ContentType.json,
        );
        return;
      }
      if ((mode == 'pokemon' || mode == 'pokemon-gift' ||
              mode == 'pokemon-encoded') &&
          request.uri.path == '/api/v1/user/info') {
        if (mode == 'pokemon-encoded') {
          await _write(
            request,
            _pokemonEncoded('''
              {"data":{"email":"encoded@example.com","u":1024,"d":2048,"transfer_enable":4096,"expired_at":1893456000}}
            '''),
            ContentType.json,
          );
          return;
        }
        await _write(
          request,
          jsonEncode({
            'data': {
              'email': 'trainer@example.com',
              'u': 1024,
              'd': 2048,
              'transfer_enable': 4096,
              'expired_at': 1893456000,
            },
          }),
          ContentType.json,
        );
        return;
      }
      if (mode == 'pokemon-405' &&
          request.uri.path == '/api/v1/user/info') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      if (mode == 'pokemon-403' &&
          request.uri.path == '/api/v1/user/info') {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      if (mode == 'pokemon-405' && request.uri.path == '/') {
        await _write(
          request,
          _wrappedHtml('''
            <html><body>
              email: fallback@example.com
              <div>剩余流量 <span class="counter">3</span> GB</div>
              <div>总流量 <span class="counter">10</span> GB</div>
            </body></html>
          '''),
          ContentType.html,
        );
        return;
      }
      if (mode == 'pokemon-403' && request.uri.path == '/') {
        await _write(
          request,
          _wrappedHtml('''
            <html><body>
              email: fallback-403@example.com
              <div>剩余流量 <span class="counter">2</span> GB</div>
              <div>总流量 <span class="counter">8</span> GB</div>
            </body></html>
          '''),
          ContentType.html,
        );
        return;
      }
      if ((mode == 'pokemon' || mode == 'pokemon-gift' ||
              mode == 'pokemon-encoded') &&
          request.uri.path == '/api/v1/user/getSubscribe') {
        if (mode == 'pokemon-encoded') {
          await _write(
            request,
            _pokemonEncoded('{"data":"$baseUrl/api/v1/client/subscribe?token=encoded"}'),
            ContentType.json,
          );
          return;
        }
        await _write(
          request,
          jsonEncode({'data': '$baseUrl/api/v1/client/subscribe?token=pika'}),
          ContentType.json,
        );
        return;
      }
      if (mode == 'pokemon-gift' &&
          request.uri.path == '/api/v1/user/redeemgiftcard') {
        await _write(
          request,
          jsonEncode({'data': true, 'type': 5, 'value': 30}),
          ContentType.json,
        );
        return;
      }
      if ((mode == 'pokemon' || mode == 'pokemon-gift') &&
          request.uri.path == '/api/v1/user/checkin') {
        await _write(
          request,
          jsonEncode({'ret': 1, 'msg': '签到成功'}),
          ContentType.json,
        );
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('iKun unwraps the protected page and sends an empty check-in body',
      () async {
    final session = AirportSession(
      kind: AirportKind.ikun,
      baseUrl: baseUrl,
      cookie: 'session=ok',
    );
    final service = AirportService();

    final snapshot = await service.sync(session);
    expect(snapshot.accountLabel, 'user@example.com');
    expect(snapshot.upload, 1048576);
    expect(snapshot.download, 2097152);
    expect(snapshot.total, 10485760);
    expect(snapshot.expireAt, isNotNull);
    expect(snapshot.subscriptionUrl,
        '$baseUrl/api/v1/client/subscribe?token=abc');

    final checkedIn = await service.checkIn(session);
    expect(checkedIn.checkinDone, isTrue);
    expect(checkedIn.message, '获得了 100 MB 流量');
    expect(requests['POST /user/checkin'], isEmpty);
  });

  test('iKun parses the current dashboard traffic labels and link subscription',
      () async {
    mode = 'ikun-current';
    final session = AirportSession(
      kind: AirportKind.ikun,
      baseUrl: baseUrl,
      cookie: 'session=ok',
    );

    final snapshot = await AirportService().sync(session);

    expect(snapshot.upload, 0);
    expect(snapshot.download, 2 * 1024 * 1024);
    expect(snapshot.total, 3 * 1024 * 1024 * 1024 + 2 * 1024 * 1024);
    expect(snapshot.subscriptionUrl,
        'https://sub.example/link/secret-token?extend=1');
  });

  test('iKun reads a real link from subscription history, not its page URL',
      () async {
    mode = 'ikun-log';
    final session = AirportSession(
      kind: AirportKind.ikun,
      baseUrl: baseUrl,
      cookie: 'session=ok',
    );

    final snapshot = await AirportService().sync(session);

    expect(snapshot.accountLabel, 'log@example.com');
    expect(snapshot.subscriptionUrl, '$baseUrl/link/log-token');
  });

  test('Pokemon reads V2Board data, subscription and check-in result',
      () async {
    mode = 'pokemon';
    final session = AirportSession(
      kind: AirportKind.pokemon,
      baseUrl: baseUrl,
      cookie: 'session=ok',
      localStorageJson: '{"token":"token-123"}',
    );
    final service = AirportService();

    final snapshot = await service.sync(session);
    expect(snapshot.accountLabel, 'trainer@example.com');
    expect(snapshot.upload, 1024);
    expect(snapshot.download, 2048);
    expect(snapshot.total, 4096);
    expect(snapshot.subscriptionUrl,
        '$baseUrl/api/v1/client/subscribe?token=pika');
    expect(snapshot.expireAt, isNotNull);

    final checkedIn = await service.checkIn(session);
    expect(checkedIn.checkinDone, isTrue);
    expect(checkedIn.message, '签到成功');
    expect(requests['POST /api/v1/user/checkin'], isEmpty);
  });

  test('Pokemon unwraps the quoted encrypted response used by the web client',
      () async {
    mode = 'pokemon-encoded';
    final session = AirportSession(
      kind: AirportKind.pokemon,
      baseUrl: baseUrl,
      cookie: 'session=ok',
      localStorageJson: '{"auth_data":"opaque-token"}',
    );

    final snapshot = await AirportService().sync(session);

    expect(snapshot.accountLabel, 'encoded@example.com');
    expect(snapshot.upload, 1024);
    expect(snapshot.download, 2048);
    expect(snapshot.total, 4096);
    expect(snapshot.subscriptionUrl,
        '$baseUrl/api/v1/client/subscribe?token=encoded');
  });

  test('Pokemon falls back when an optional API answers HTTP 405', () async {
    mode = 'pokemon-405';
    final session = AirportSession(
      kind: AirportKind.pokemon,
      baseUrl: baseUrl,
      cookie: 'session=ok',
      localStorageJson: '{"token":"token-123"}',
    );

    final snapshot = await AirportService().sync(session);

    expect(snapshot.accountLabel, 'fallback@example.com');
    expect(snapshot.total, 10 * 1024 * 1024 * 1024);
    expect(requests.containsKey('GET /api/v1/user/info'), isTrue);
    expect(requests.containsKey('GET /'), isTrue);
  });

  test('Pokemon keeps the account when the API answers HTTP 403', () async {
    mode = 'pokemon-403';
    final session = AirportSession(
      kind: AirportKind.pokemon,
      baseUrl: baseUrl,
      cookie: 'session=ok',
      localStorageJson: '{"token":"token-123"}',
    );

    final snapshot = await AirportService().sync(session);

    expect(snapshot.accountLabel, 'fallback-403@example.com');
    expect(snapshot.total, 8 * 1024 * 1024 * 1024);
    expect(requests.containsKey('GET /api/v1/user/info'), isTrue);
    expect(requests.containsKey('GET /'), isTrue);
  });

  test('Pokemon redeems the monthly gift card and sends the official field',
      () async {
    mode = 'pokemon-gift';
    final session = AirportSession(
      kind: AirportKind.pokemon,
      baseUrl: baseUrl,
      cookie: 'session=ok',
      localStorageJson: '{"auth_data":"Bearer token-123"}',
    );

    final result = await AirportService().redeemGiftCard(session, 'APRIL-88');

    expect(result.type, 5);
    expect(result.value, 30);
    expect(result.message, '兑换成功，订阅套餐增加 30 天');
    expect(requests['POST /api/v1/user/redeemgiftcard'], contains('APRIL-88'));
  });
}

String _wrappedHtml(String html) {
  final encoded = base64Encode(utf8.encode(html));
  return '<script>var originBody = "$encoded"; '
      'document.write(decodeBase64(originBody));</script>';
}

Future<void> _write(
  HttpRequest request,
  String body,
  ContentType contentType,
) async {
  request.response.headers.contentType = contentType;
  request.response.write(body);
  await request.response.close();
}

String _pokemonEncoded(String json) {
  const encrypted =
      'nsz{gAWrkXlx08J6Eq:V4[deO1DQTCwm2oB3ty9jSYI]7RM5bHiUam,c}KuPGpNhZLvF';
  const plain =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,[]{}:';
  var value = json.trim();
  for (var round = 0; round < 10; round++) {
    value = value.split('').map((character) {
      final index = plain.indexOf(character);
      return index < 0 ? character : encrypted[index];
    }).join();
  }
  return '"${base64Encode(utf8.encode(value))}"';
}
