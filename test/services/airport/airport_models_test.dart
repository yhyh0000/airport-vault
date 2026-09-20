import 'package:fl_clash/services/airport/airport_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('airport entries use the current reachable discovery domains', () {
    final ikun = airportSite(AirportKind.ikun);
    final pokemon = airportSite(AirportKind.pokemon);

    expect(ikun.defaultBaseUrl, 'https://ikuuu.top');
    expect(pokemon.defaultBaseUrl, 'https://web2.52pokemon.cc');
    expect(pokemon.alternateBaseUrls, contains('https://love.52pokemon.cc'));
    expect(pokemon.loginUrl(pokemon.defaultBaseUrl),
        'https://web2.52pokemon.cc/#/login');
  });

  test('airport session reads token and survives secure-store serialization', () {
    const session = AirportSession(
      kind: AirportKind.pokemon,
      baseUrl: 'https://web2.52pokemon.cc',
      cookie: 'session=abc',
      localStorageJson: '{"token":"token-123"}',
    );

    expect(session.accessToken, 'token-123');
    final restored = AirportSession.fromJson(session.toJson());
    expect(restored.kind, AirportKind.pokemon);
    expect(restored.cookie, 'session=abc');
    expect(restored.accessToken, 'token-123');
  });
}
