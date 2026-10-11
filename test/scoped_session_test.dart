import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fafu_kebiao/models/course.dart';
import 'package:fafu_kebiao/services/scoped_session.dart';
import 'package:fafu_kebiao/services/store.dart';
import 'package:fafu_kebiao/services/sync_service.dart';
import 'package:fafu_kebiao/services/timetable_api.dart';

const casSecret = 'fictional-cas-cookie';
const gatewaySecret = 'fictional-gateway-cookie';
const accessSecret = 'fictional-access-token';

SchoolCookies casJar() => SchoolCookies([
  const SessionCookie(name: 'CASTGC', value: casSecret, domain: schoolAuthHost,
      path: '/authserver', secure: false),
]);

http.Response jsonResponse(Object value) => http.Response(jsonEncode(value), 200,
    headers: {'content-type': 'application/json'});

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('CAS survives reloading preferences; old access token is not reused', () async {
    await Store.saveSchoolCookies(casJar());
    await Store.saveToken('fictional-expired-access');
    await Store.saveCasHttpAllowed(true);
    await Store.init();
    final jar = Store.schoolCookies;
    final requests = <http.Request>[];
    final client = SchoolSessionClient(jar, allowAuthHttp: Store.casHttpAllowed,
      client: MockClient((request) async {
        requests.add(request);
        expect(request.followRedirects, isFalse);
        expect(request.headers['authorization'], isNull);
        if (request.url.host == schoolAuthHost) {
          expect(request.url.scheme, 'http');
          expect(request.headers['cookie'], contains(casSecret));
          return http.Response('', 302, headers: {
            'location': 'https://task.fafu.edu.cn/timetable?ticket=fictional-new-ticket'});
        }
        expect(request.headers['cookie'] ?? '', isNot(contains('CASTGC')));
        if (request.url.path == '/api/he/token') {
          expect(request.headers['cookie'], contains(gatewaySecret));
          return jsonResponse({'data': {'access_token': accessSecret}});
        }
        if (request.url.queryParameters.containsKey('ticket')) {
          return http.Response('', 302, headers: {
            'set-cookie': 'NGXCAS=$gatewaySecret; Path=/; Secure; HttpOnly',
            'location': 'http://task.fafu.edu.cn/timetable/'});
        }
        if (request.url.path == '/timetable/') return http.Response('page', 200);
        return http.Response('', 302, headers: {
          'location': 'http://auth.fafu.edu.cn/authserver/login?service=fictional'});
      }));
    expect(await client.ensureAuthenticated(), accessSecret);
    expect(requests.length, 5);
    expect(jar.hasGateway, isTrue);
    expect(requests.where((r) => r.url.host == schoolTaskHost)
        .every((r) => r.url.scheme == 'https'), isTrue);
    client.close();
  });

  test('HTTP is not attempted until explicitly allowed', () async {
    var requests = 0;
    final client = SchoolSessionClient(casJar(), allowAuthHttp: false,
      client: MockClient((request) async {
        requests++;
        return http.Response('', 200);
      }));
    await expectLater(client.ensureAuthenticated(), throwsA(
        isA<SchoolLoginException>().having((e) => e.failure, 'failure',
            LoginFailure.needsHttpPermission)));
    expect(requests, 0);
    client.close();
  });

  test('old gateway failure falls back to saved CAS; token endpoint is corrected', () async {
    final jar = casJar()..addLegacyGateway('NGXCAS=fictional-old-gateway; CASTGC=wrong-origin');
    final urls = <Uri>[];
    final client = SchoolSessionClient(jar, allowAuthHttp: true,
      client: MockClient((request) async {
        urls.add(request.url);
        if (request.url.path == '/api/he/token') {
          if (request.headers['cookie']!.contains('fictional-old-gateway')) {
            return http.Response('', 302, headers: {'location': 'http://auth.fafu.edu.cn/authserver/login'});
          }
          return jsonResponse({'access_token': accessSecret});
        }
        if (request.url.host == schoolAuthHost) {
          expect(request.headers['cookie'], 'CASTGC=$casSecret');
          return http.Response('', 302, headers: {
            'location': 'https://task.fafu.edu.cn/timetable?ticket=fictional-fresh-ticket'});
        }
        if (request.url.hasQuery) {
          return http.Response('', 302, headers: {'set-cookie': 'NGXCAS=$gatewaySecret; Path=/; Secure',
              'location': '/timetable/'});
        }
        if (request.url.path == '/timetable/') return http.Response('page', 200);
        expect(request.headers['cookie'], isNull);
        return http.Response('', 302, headers: {
          'location': 'http://auth.fafu.edu.cn/authserver/login?service=fictional'});
      }));
    expect(await client.ensureAuthenticated(), accessSecret);
    expect(urls.first.path, '/api/he/token');
    expect(urls.any((u) => u.path == '/api8/api/he/token'), isFalse);
    client.close();
  });

  test('native WeLink auth-code page is recognized without executing or replaying it', () async {
    var requests = 0;
    final client = SchoolSessionClient(casJar(), allowAuthHttp: true,
      client: MockClient((request) async {
        requests++;
        if (request.url.host == schoolTaskHost) {
          return http.Response('', 302, headers: {
            'location': 'http://auth.fafu.edu.cn/authserver/freeLogin.do?providerType=WeLink'});
        }
        return http.Response('<script>HWH5.getAuthCode()</script>', 200);
      }));
    await expectLater(client.ensureAuthenticated(), throwsA(
        isA<SchoolLoginException>().having((e) => e.failure, 'failure',
            LoginFailure.nativeClientRequired)));
    expect(requests, 2);
    client.close();
  });

  test('foreign redirects are blocked before sending any second request', () async {
    var requests = 0;
    final client = SchoolSessionClient(casJar(), allowAuthHttp: true,
      client: MockClient((request) async {
        requests++;
        return http.Response('', 302, headers: {
          'location': 'https://evil.invalid/steal?ticket=fictional-secret'});
      }));
    await expectLater(client.ensureAuthenticated(), throwsA(isA<SchoolTransportException>()));
    expect(requests, 1);
    client.close();
  });

  test('transport exceptions do not expose credential-bearing library error text', () async {
    final client = SchoolSessionClient(casJar(), allowAuthHttp: true,
      client: MockClient((request) async {
        throw http.ClientException('Cookie=$casSecret; ticket=fictional-secret');
      }));
    try {
      await client.ensureAuthenticated();
      fail('Expected a transport failure');
    } catch (e) {
      expect(e, isA<SchoolTransportException>());
      expect('$e', isNot(contains(casSecret)));
      expect('$e', isNot(contains('fictional-secret')));
    } finally { client.close(); }
  });

  test('cookie domain, Secure, expiry and path boundaries are enforced', () {
    final jar = casJar()..addLegacyGateway('NGXCAS=$gatewaySecret; CASTGC=foreign');
    expect(jar.headerFor(schoolTokenUri), 'NGXCAS=$gatewaySecret');
    expect(jar.headerFor(schoolAuthCookieUri), 'CASTGC=$casSecret');
    expect(jar.headerFor(Uri.http(schoolTaskHost, '/api/he/token')), isEmpty);
    expect(jar.headerFor(Uri.http(schoolAuthHost, '/authserver-evil/login')), isEmpty);
    expect(jar.headerFor(Uri.https('evil.invalid', '/authserver/login')), isEmpty);
    jar.put(SessionCookie(name: 'expired', value: 'fictional-old', domain: schoolAuthHost,
        path: '/authserver', secure: false, expires: DateTime.utc(2000)));
    expect(jar.headerFor(schoolAuthCookieUri), isNot(contains('fictional-old')));
  });

  test('Set-Cookie with Expires commas and Max-Age deletion is parsed correctly', () {
    final jar = casJar();
    jar.absorb(http.Response('', 200, headers: {'set-cookie':
      'route=fictional-route; Path=/authserver; Expires=Thu, 01 Jan 2099 00:00:00 GMT, '
      'CASTGC=removed; Path=/authserver; Max-Age=0'}), schoolAuthCookieUri);
    expect(jar.hasCas, isFalse);
    expect(jar.headerFor(schoolAuthCookieUri), contains('route=fictional-route'));
  });

  test('a parent-domain cookie is restricted to its source host; edu.cn is rejected', () {
    final jar = casJar();
    jar.absorb(http.Response('', 200, headers: {'set-cookie':
      'route=fictional-parent; Domain=fafu.edu.cn; Path=/, '
      'CASTGC=fictional-wide; Domain=edu.cn; Path=/'}), schoolAuthCookieUri);
    expect(jar.headerFor(schoolTokenUri), isEmpty);
    expect(jar.headerFor(schoolAuthCookieUri), contains(casSecret));
    expect(jar.headerFor(schoolAuthCookieUri), isNot(contains('fictional-wide')));
  });

  test('input cookie injection and unsafe HTTP URLs are rejected', () {
    expect(SessionCookie.fromJson({
      'name': 'CASTGC', 'value': 'bad\r\nAuthorization: value',
      'domain': schoolAuthHost, 'path': '/authserver', 'secure': false}), isNull);
    for (final uri in [
      Uri.parse('http://auth.fafu.edu.cn:8080/authserver/login'),
      Uri.parse('http://auth.fafu.edu.cn/api/he/token'),
      Uri.parse('http://user:password@auth.fafu.edu.cn/authserver/login'),
      Uri.parse('http://task.fafu.edu.cn/authserver/login'),
    ]) {
      expect(() => SchoolSessionClient.checkedUri(uri, allowAuthHttp: true),
          throwsA(isA<SchoolTransportException>()));
    }
  });

  test('session JSON import excludes JWTs and one-time codes', () {
    final jar = SchoolCookies.fromExport(jsonEncode({
      'format': 'fafu_sso_session_v1', 'cookies': casJar().toJson(),
      'access_token': 'fictional-expired-access', 'code': 'fictional-old-code',
    }));
    expect(jar.hasCas, isTrue);
    expect(jsonEncode(jar.toJson()), isNot(contains('fictional-expired-access')));
    expect(jsonEncode(jar.toJson()), isNot(contains('fictional-old-code')));
    expect(() => SchoolCookies.fromExport('{}'), throwsFormatException);
  });

  test('offline sync keeps cached courses and reports network failure', () async {
    const course = Course(name: 'Fixture course', teacher: '', place: '',
      weekday: 1, periods: [1, 2], weeksRaw: '第1-16周', weekType: '每周');
    await Store.saveSchedule(const Schedule(courses: [course]));
    await Store.saveSchoolCookies(casJar());
    await Store.saveCasHttpAllowed(true);
    final result = await http.runWithClient(
      SyncService.refreshWithStoredSession,
      () => MockClient((request) async {
        throw http.ClientException('Cookie=$casSecret');
      }),
    );
    expect(result.status, RefreshStatus.networkError);
    expect(Store.schedule.courses.single.name, course.name);
    expect(Store.schoolCookies.hasCas, isTrue);
    expect(result.message, isNot(contains(casSecret)));
    expect(Store.lastSync, isNull);
  });

  test('failed semester week propagates rather than silently removing courses', () async {
    final api = TimetableApi(token: accessSecret, cookie: 'NGXCAS=$gatewaySecret');
    await http.runWithClient(() async {
      await expectLater(api.fetchSemester(info: WeekInfo('fixture-year', '1', 1, '')),
          throwsA(isA<SchoolTransportException>()));
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/teaching-week/list')) {
        return jsonResponse({'code': 200, 'data': [{'weekIndex': 1}, {'weekIndex': 2}]});
      }
      if (request.url.queryParameters['weekIndex'] == '2') {
        return http.Response('temporary failure', 503);
      }
      return jsonResponse({'code': 200, 'data': []});
    }));
  });

  test('concurrent sync requests share a single operation', () async {
    final first = SyncService.refreshWithStoredSession();
    final second = SyncService.refreshWithStoredSession();
    expect(identical(first, second), isTrue);
    expect((await first).status, RefreshStatus.noSession);
  });
}
