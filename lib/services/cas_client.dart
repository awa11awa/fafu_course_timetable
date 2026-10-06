import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as enc;

import 'timetable_api.dart';

/// 静默 CAS 登录失败的原因
enum CasFailReason {
  /// 需要验证码/滑块，人机验证过不了，只能手动
  captchaRequired,
  /// 账号或密码错误
  badCredentials,
  /// 网络问题
  network,
  /// 未知（页面结构变了等）
  unknown,
}

class CasLoginException implements Exception {
  final CasFailReason reason;
  final String message;
  CasLoginException(this.reason, this.message);
  @override
  String toString() => message;
}

/// 静默统一身份认证登录（无 WebView，纯 HTTP）。
///
/// 流程（2026-10 实测 auth.fafu.edu.cn）：
///   1. GET 登录页 → 解析 lt / execution / pwdEncryptSalt，检查 needCaptcha
///   2. 用户名、密码按页面 JS 做 AES-CBC 加密（随机64字符+明文，salt 为 key）
///   3. POST 表单 → 手动跟随重定向（CAS → ehall → 网关），全程收集 Cookie
///   4. 拿到网关 Cookie（NGXCAS）即成功
///
/// 任何一步失败都抛 [CasLoginException]，调用方回退到 WebView 手动登录。
class CasClient {
  static const String _defaultSalt = 'rjBFAaHsNkKAhpoi';
  static const String _aesChars =
      'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  final Map<String, String> _cookies = {};

  static const String _ua = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  String _rand(int n) {
    final r = Random.secure();
    return String.fromCharCodes(
        List.generate(n, (_) => _aesChars.codeUnitAt(r.nextInt(_aesChars.length))));
  }

  /// 页面 JS 的 encryptPassword：AES-CBC-Pkcs7(base64)，明文 = 随机64字符 + 原文
  String _encryptPassword(String plain, String salt) {
    final s = salt.trim();
    if (s.isEmpty) return plain;
    final key = enc.Key.fromUtf8(s);
    final iv = enc.IV.fromUtf8(_rand(16));
    final encrypter =
        enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'));
    return encrypter.encrypt(_rand(64) + plain, iv: iv).base64;
  }

  String get _cookieHeader => _cookies.entries
      .map((e) => '${e.key}=${e.value}')
      .join('; ');

  void _collect(HttpClientResponse resp) {
    for (final c in resp.cookies) {
      if (c.name.isNotEmpty && c.value.isNotEmpty) {
        _cookies[c.name] = c.value;
      }
    }
  }

  /// 手动跟随重定向（最多 [maxHops] 跳），返回最终 URL 和页面内容
  Future<({Uri url, String body, int status})> _follow(Uri start,
      {int maxHops = 12}) async {
    var uri = start;
    String body = '';
    var status = 0;
    for (var i = 0; i < maxHops; i++) {
      final req = await _http.getUrl(uri);
      req.followRedirects = false;
      req.headers.set('User-Agent', _ua);
      if (_cookies.isNotEmpty) req.headers.set('Cookie', _cookieHeader);
      final resp = await req.close().timeout(const Duration(seconds: 25));
      _collect(resp);
      status = resp.statusCode;
      body = await resp.transform(utf8.decoder).join();
      final loc = resp.headers.value('location');
      if ((status == 301 || status == 302 || status == 303 || status == 307 || status == 308) &&
          loc != null &&
          loc.isNotEmpty) {
        uri = uri.resolve(loc);
        continue;
      }
      // HTML meta refresh 兜底
      final meta = RegExp(
              r'''<meta[^>]+http-equiv=["']refresh["'][^>]+url=([^"'>]+)''',
              caseSensitive: false)
          .firstMatch(body);
      if (meta != null) {
        uri = uri.resolve(meta.group(1)!.trim());
        continue;
      }
      break;
    }
    return (url: uri, body: body, status: status);
  }

  String? _inputValue(String html, String name) {
    final m = RegExp(
            '<input[^>]+name="$name"[^>]*value="([^"]*)"',
            caseSensitive: false)
        .firstMatch(html);
    return m?.group(1);
  }

  String? _jsVar(String html, String name) {
    final m = RegExp('$name\\s*=\\s*"([^"]*)"').firstMatch(html);
    return m?.group(1);
  }

  /// 静默登录。成功返回网关 Cookie 字符串（含 NGXCAS）；失败抛 [CasLoginException]。
  Future<String> silentLogin(String username, String password) async {
    try {
      // 1. 取登录页（跟随重定向，拿到最终 HTML）
      final loginUri = Uri.parse(TimetableApi.casLoginUrl);
      final first = await _follow(loginUri, maxHops: 5);
      final page = first.body;
      if (!page.contains('username') && !page.contains('password')) {
        throw CasLoginException(
            CasFailReason.unknown, '登录页加载异常，页面结构可能已变化');
      }

      // 2. 验证码检查：页面 JS 变量 needCaptcha 非空 → 必须人机验证
      final needCaptcha = _jsVar(page, 'needCaptcha') ?? '';
      if (needCaptcha.isNotEmpty) {
        throw CasLoginException(
            CasFailReason.captchaRequired, '需要验证码，请手动完成一次登录');
      }
      // 验证码输入框可见 → 同样回退手动
      if (RegExp(r'id="captchaDiv"[^>]*class="[^"]*captcha item[^"]*"')
              .hasMatch(page) &&
          !page.contains('captcha item hide')) {
        throw CasLoginException(
            CasFailReason.captchaRequired, '需要验证码，请手动完成一次登录');
      }

      final lt = _inputValue(page, 'lt') ?? '';
      final execution = _inputValue(page, 'execution') ?? 'e1s1';
      final salt = _inputValue(page, 'pwdEncryptSalt') ?? '';

      // 3. 按页面 JS 加密账号密码
      final encUser = _encryptPassword(username, _defaultSalt);
      final encPass = _encryptPassword(password, salt);

      // 4. POST 登录表单
      final form = {
        'username': encUser,
        'password': encPass,
        'lt': lt,
        'execution': execution,
        '_eventId': 'submit',
        'cllt': 'userNameLogin',
        'dllt': 'generalLogin',
      };
      final postUri = first.url;
      final postReq = await _http.postUrl(postUri);
      postReq.followRedirects = false;
      postReq.headers.set('User-Agent', _ua);
      postReq.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      postReq.headers.set('Referer', postUri.toString());
      if (_cookies.isNotEmpty) {
        postReq.headers.set('Cookie', _cookieHeader);
      }
      postReq.write(form.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&'));
      final postResp = await postReq.close().timeout(const Duration(seconds: 25));
      _collect(postResp);
      final postBody = await postResp.transform(utf8.decoder).join();

      // 5. 登录失败：还在登录页（无跳转或带错误提示）
      final loc = postResp.headers.value('location');
      final stillLogin = (postResp.statusCode == 200) &&
          (postBody.contains('authserver/login') ||
              postBody.contains('用户名或密码') ||
              postBody.contains('请输入验证码'));
      if (stillLogin || (loc == null && postResp.statusCode == 200)) {
        // 区分一下是密码错还是触发了验证码
        if (postBody.contains('验证码') && !postBody.contains('captcha item hide')) {
          throw CasLoginException(
              CasFailReason.captchaRequired, '触发了验证码，请手动完成一次登录');
        }
        throw CasLoginException(
            CasFailReason.badCredentials, '账号或密码不正确，请检查后重试');
      }

      // 6. 跟随重定向链（CAS → ehall → 网关）
      Uri next = loc != null && loc.isNotEmpty
          ? postUri.resolve(loc)
          : postUri;
      final fin = await _follow(next);

      // 7. 还没拿到 NGXCAS？带着现有 Cookie 直接访问课表网关触发一次
      if (!_cookies.containsKey(TimetableApi.gatewayCookie)) {
        await _follow(Uri.parse(TimetableApi.timetablePage));
      }

      final ngxc = _cookies[TimetableApi.gatewayCookie];
      if (ngxc == null || ngxc.isEmpty) {
        throw CasLoginException(
            CasFailReason.unknown, '登录后未获取到会话 Cookie，已回退手动登录');
      }
      return _cookieHeader;
    } on CasLoginException {
      rethrow;
    } on SocketException catch (e) {
      throw CasLoginException(CasFailReason.network, '网络不通：${e.message}');
    } on TimeoutException {
      throw CasLoginException(CasFailReason.network, '请求超时，请检查网络后重试');
    } catch (e) {
      throw CasLoginException(CasFailReason.unknown, '静默登录失败：$e');
    } finally {
      _http.close(force: true);
    }
  }
}
