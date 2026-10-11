import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const schoolAuthHost = 'auth.fafu.edu.cn';
const schoolTaskHost = 'task.fafu.edu.cn';
final schoolTokenUri = Uri.https(schoolTaskHost, '/api/he/token');
final schoolEntryUri = Uri.https(schoolTaskHost, '/timetable');
final schoolAuthCookieUri = Uri.http(schoolAuthHost, '/authserver/login');

enum LoginFailure { noSession, needsHttpPermission, loginRequired, nativeClientRequired }

class SchoolLoginException implements Exception {
  final LoginFailure failure;
  const SchoolLoginException(this.failure);

  @override
  String toString() => switch (failure) {
        LoginFailure.noSession => '尚未保存学校登录会话，请先登录或导入会话',
        LoginFailure.needsHttpPermission => '需要允许学校的 HTTP 认证才能恢复登录',
        LoginFailure.loginRequired => '学校登录会话未能恢复，请重新登录',
        LoginFailure.nativeClientRequired => '学校要求数字 FAFU 生成新的免登码，请重新登录或更新学校会话',
      };
}

class SchoolTransportException implements Exception {
  final String message;
  const SchoolTransportException([this.message = '连接学校服务失败，请检查网络后重试']);
  @override
  String toString() => message;
}

/// 每条 Cookie 保留来源域名、路径、Secure 和已知有效期；会话 Cookie
/// 也保存到本机，但学校服务器仍决定其是否有效。
class SessionCookie {
  final String name, value, domain, path;
  final bool secure;
  final DateTime? expires;
  const SessionCookie({
    required this.name, required this.value, required this.domain,
    required this.path, required this.secure, this.expires,
  });

  bool get expired => expires != null && !expires!.isAfter(DateTime.now().toUtc());

  bool matches(Uri uri) {
    final pathMatches = uri.path == path ||
        (uri.path.startsWith(path) && (path.endsWith('/') ||
            (uri.path.length > path.length && uri.path[path.length] == '/')));
    return !expired && domain == uri.host && pathMatches &&
        (!secure || uri.scheme == 'https');
  }

  Map<String, dynamic> toJson() => {
    'name': name, 'value': value, 'domain': domain, 'path': path, 'secure': secure,
    'expires': expires == null ? null : expires!.millisecondsSinceEpoch ~/ 1000,
  };

  static SessionCookie? fromJson(Object? input) {
    if (input is! Map) return null;
    final name = input['name'], value = input['value'], domain = input['domain'];
    final path = input['path'], secure = input['secure'], seconds = input['expires'];
    if (name is! String || value is! String || domain is! String ||
        path is! String || secure is! bool ||
        !{schoolAuthHost, schoolTaskHost}.contains(domain) ||
        name.isEmpty || !path.startsWith('/') ||
        RegExp(r'[\x00-\x20\x7f;=]').hasMatch(name) ||
        RegExp(r'[\x00-\x1f\x7f;]').hasMatch(value + path) ||
        (seconds != null && seconds is! num)) {
      return null;
    }
    DateTime? expiry;
    try {
      if (seconds != null) {
        expiry = DateTime.fromMillisecondsSinceEpoch((seconds as num).toInt() * 1000, isUtc: true);
      }
    } catch (_) { return null; }
    return SessionCookie(name: name, value: value, domain: domain, path: path,
        secure: secure, expires: expiry);
  }
}

class SchoolCookies {
  final List<SessionCookie> _cookies;
  SchoolCookies([Iterable<SessionCookie> cookies = const []])
      : _cookies = cookies.where((c) => !c.expired).toList();

  bool get hasCas => _cookies.any((c) => c.domain == schoolAuthHost &&
      c.name == 'CASTGC' && c.value.isNotEmpty && !c.expired);
  bool get hasGateway => _cookies.any((c) => c.domain == schoolTaskHost &&
      c.name == 'NGXCAS' && c.value.isNotEmpty && !c.expired);
  List<Map<String, dynamic>> toJson() => _cookies.where((c) => !c.expired)
      .map((c) => c.toJson()).toList();
  static SchoolCookies fromJson(Object? value) => SchoolCookies(
      value is List ? value.map(SessionCookie.fromJson).whereType<SessionCookie>() : []);

  static SchoolCookies fromExport(String text) {
    final Object? data;
    try { data = jsonDecode(text); } catch (_) {
      throw const FormatException('会话文件不是完整的 JSON');
    }
    if (data is! Map || data['format'] != 'fafu_sso_session_v1') {
      throw const FormatException('请选择本机保存的 fafu_sso_session 文件');
    }
    final jar = fromJson(data['cookies']);
    if (!jar.hasCas) throw const FormatException('文件中没有有效的学校 CAS 会话');
    return jar;
  }

  void put(SessionCookie cookie) {
    _cookies.removeWhere((old) => old.name == cookie.name &&
        old.domain == cookie.domain && old.path == cookie.path);
    if (!cookie.expired && cookie.value.isNotEmpty) _cookies.add(cookie);
  }

  void addHeader(String header, Uri origin, {String? path}) {
    for (final pair in header.split(';')) {
      final equal = pair.indexOf('=');
      if (equal <= 0) continue;
      final c = SessionCookie.fromJson({
        'name': pair.substring(0, equal).trim(),
        'value': pair.substring(equal + 1).trim(), 'domain': origin.host,
        'path': path ?? (origin.host == schoolAuthHost ? '/authserver' : '/'),
        'secure': origin.scheme == 'https', 'expires': null,
      });
      if (c != null) put(c);
    }
  }

  void addLegacyGateway(String header) {
    for (final pair in header.split(';')) {
      if (pair.trim().startsWith('NGXCAS=')) addHeader(pair, schoolTokenUri);
    }
  }

  String headerFor(Uri uri) {
    final cookies = _cookies.where((c) => c.matches(uri)).toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  void discardGateway() => _cookies.removeWhere((c) => c.domain == schoolTaskHost);

  void absorb(http.Response response, Uri origin) {
    final header = response.headers['set-cookie'];
    if (header == null) return;
    // Keep the comma in Expires, split only at a new cookie name followed by '='.
    for (final part in header.split(RegExp(r',(?=\s*[^=;,\s]+\s*=)'))) {
      try {
        final cookie = Cookie.fromSetCookieValue(part.trim());
        final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
        if (domain != null && domain != origin.host && domain != 'fafu.edu.cn') continue;
        final expiry = cookie.maxAge != null
            ? DateTime.now().toUtc().add(Duration(seconds: cookie.maxAge!))
            : cookie.expires;
        final parsed = SessionCookie.fromJson({
          'name': cookie.name, 'value': cookie.value, 'domain': origin.host,
          'path': cookie.path ?? (origin.host == schoolAuthHost ? '/authserver' : '/'),
          'secure': cookie.secure,
          'expires': expiry == null ? null : expiry.millisecondsSinceEpoch ~/ 1000,
        });
        if (parsed != null) put(parsed);
      } catch (_) { /* Ignore malformed server cookies. */ }
    }
  }
}

/// Manual redirects keep school credentials on their own origins. HTTP is
/// allowed only for the observed authentication paths after explicit consent.
class SchoolSessionClient {
  final SchoolCookies cookies;
  final bool allowAuthHttp;
  final http.Client _client;
  SchoolSessionClient(this.cookies, {required this.allowAuthHttp, http.Client? client})
      : _client = client ?? http.Client();
  void close() => _client.close();

  static Uri checkedUri(Uri uri, {required bool allowAuthHttp}) {
    const authPaths = {'/authserver/login', '/authserver/freeLogin.do', '/authserver/callback'};
    const taskPaths = {'/timetable', '/timetable/', '/api/he/token'};
    final allowedPaths = uri.host == schoolAuthHost ? authPaths : taskPaths;
    if (!{schoolAuthHost, schoolTaskHost}.contains(uri.host) ||
        !{'http', 'https'}.contains(uri.scheme) || uri.userInfo.isNotEmpty ||
        uri.hasFragment || !allowedPaths.contains(uri.path) ||
        (uri.hasPort && uri.port != (uri.scheme == 'http' ? 80 : 443))) {
      throw const SchoolTransportException('学校认证跳转到未支持的地址，已停止');
    }
    if (uri.host == schoolTaskHost && uri.scheme == 'http') {
      return uri.replace(scheme: 'https', port: 443);
    }
    if (uri.scheme == 'http' && !allowAuthHttp) {
      throw const SchoolLoginException(LoginFailure.needsHttpPermission);
    }
    return uri;
  }

  Future<http.Response> _request(Uri original) async {
    final uri = checkedUri(original, allowAuthHttp: allowAuthHttp);
    final header = cookies.headerFor(uri);
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'application/json, text/html, */*',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 17; wv) AppleWebKit/537.36 '
            'Chrome/153.0.0.0 Mobile Safari/537.36',
        if (uri.host == schoolTaskHost) 'X-APP-CODE': 'timetable',
        if (header.isNotEmpty) 'Cookie': header,
      });
    try {
      final stream = await _client.send(request).timeout(const Duration(seconds: 25));
      final response = await _boundedResponse(stream).timeout(const Duration(seconds: 25));
      if (response.statusCode >= 500) {
        throw const SchoolTransportException('学校服务暂时异常，请稍后重试');
      }
      cookies.absorb(response, uri);
      return response;
    } on SchoolTransportException { rethrow; }
    catch (_) { throw const SchoolTransportException(); }
  }

  static Future<http.Response> _boundedResponse(http.StreamedResponse stream) async {
    final buffer = BytesBuilder(copy: false);
    await for (final bytes in stream.stream) {
      if (buffer.length + bytes.length > 2 * 1024 * 1024) {
        throw const SchoolTransportException('学校响应超过可读取范围');
      }
      buffer.add(bytes);
    }
    return http.Response.bytes(buffer.takeBytes(), stream.statusCode,
        headers: stream.headers, request: stream.request);
  }

  Future<String> _exchangeToken() async {
    final response = await _request(schoolTokenUri);
    if ({301, 302, 303, 307, 308, 401, 403}.contains(response.statusCode)) {
      throw const SchoolLoginException(LoginFailure.loginRequired);
    }
    if (response.statusCode != 200) throw const SchoolTransportException('课表令牌接口未正常响应');
    Object? object;
    try { object = jsonDecode(utf8.decode(response.bodyBytes)); } catch (_) {
      throw const SchoolTransportException('课表令牌接口未返回可用数据');
    }
    for (var depth = 0; depth < 4 && object is Map; depth++) {
      final token = object['access_token'];
      if (token is String && token.isNotEmpty &&
          !RegExp(r'[\x00-\x20\x7f]').hasMatch(token)) {
        return token;
      }
      object = object['data'];
    }
    throw const SchoolLoginException(LoginFailure.loginRequired);
  }

  Future<String> ensureAuthenticated() async {
    if (cookies.hasGateway) {
      try { return await _exchangeToken(); }
      on SchoolLoginException { /* Recover the gateway using the saved CAS session. */ }
    }
    if (!cookies.hasCas) throw const SchoolLoginException(LoginFailure.noSession);
    if (!allowAuthHttp) throw const SchoolLoginException(LoginFailure.needsHttpPermission);
    cookies.discardGateway();
    var uri = schoolEntryUri;
    for (var count = 0; count < 12; count++) {
      uri = checkedUri(uri, allowAuthHttp: allowAuthHttp);
      final response = await _request(uri);
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) throw const SchoolTransportException('学校认证跳转信息缺失');
        try {
          uri = checkedUri(uri.resolve(location), allowAuthHttp: allowAuthHttp);
        } on FormatException {
          throw const SchoolTransportException('学校认证跳转信息无法读取');
        }
        continue;
      }
      if (uri.host == schoolAuthHost) {
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        if (response.statusCode == 200 && body.contains('HWH5') && body.contains('getAuthCode')) {
          throw const SchoolLoginException(LoginFailure.nativeClientRequired);
        }
        throw const SchoolLoginException(LoginFailure.loginRequired);
      }
      if (response.statusCode != 200 || !cookies.hasGateway) {
        throw const SchoolLoginException(LoginFailure.loginRequired);
      }
      return _exchangeToken();
    }
    throw const SchoolTransportException('学校认证跳转次数过多，请稍后重试');
  }
}
