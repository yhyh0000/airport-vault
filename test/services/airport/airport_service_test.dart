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
    baseUrl = 'http://localhost:${server.port}';
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests['${request.method} ${request.uri.path}'] = body;

      if (mode == 'ikun' && request.uri.path == '/user') {
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
      if (mode == 'ikun' && request.uri.path == '/user/checkin') {
        await _write(
          request,
          jsonEncode({'ret': 1, 'msg': '获得了 100 MB 流量'}),
          ContentType.json,
        );
        return;
      }
      if (mode == 'pokemon' && request.uri.path == '/api/v1/user/info') {
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
      if (mode == 'pokemon' &&
          request.uri.path == '/api/v1/user/getSubscribe') {
        await _write(
          request,
          jsonEncode({'data': '$baseUrl/api/v1/client/subscribe?token=pika'}),
          ContentType.json,
        );
        return;
      }
      if (mode == 'pokemon' &&
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
