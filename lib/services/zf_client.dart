import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'store.dart';

/// 正方教务系统客户端（对应 Python 版逻辑）
///
/// 该系统有两个特点：
/// 1. 使用「无 Cookie 会话」——会话 ID 写在 URL 路径里，形如
///    http://jwgl.fafu.edu.cn/(xxxxxxxxxxxxxxxxxxxx)/xskbcx.aspx
/// 2. 全站 gb2312 编码，因此收发都要走 GBK 编解码
///
/// **关键坑**：访问首页 `/` 会 302 到 `/(会话ID)/default2.aspx`，会话 ID 只出现在
/// 这个跳转目标里。而 `package:http` 的 `response.request.url` 是**原始请求**的 URL，
/// 自动跟随重定向后拿不到最终地址，会导致会话 ID 丢失。所以这里一律**手动跟随重定向**。
class ZfClient {
  /// 默认校内直连；可在设置里切换为 WebVPN（校外访问）
  static const String defaultBase = 'http://jwgl.fafu.edu.cn';
  static const String gnmkdmKbcx = 'N121603'; // 学生个人课表菜单号

  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
  };

  /// 接入地址：默认校内直连，可在设置里切换为 WebVPN（校外访问）
  final String base;

  ZfClient({String? base}) : base = base ?? Store.baseUrl;

  /// 学校域名同时解析到 CERNET 的 IPv6 与 IPv4 地址。
  /// 很多网络（尤其手机流量）到该 IPv6 是黑洞路由：连接不会被立刻拒绝，
  /// 而是静默等待直到超时，表现出来就是「无法连接教务系统」。
  /// 这里强制优先 IPv4，并为连接设置短超时，避免长时间卡住。
  static http.Client buildClient() {
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 15);

    // 学校 WebVPN 入口常使用自签名证书；仅对 fafu.edu.cn 域放宽校验，
    // 其它域名仍走正常校验，避免影响整体安全性。
    io.badCertificateCallback = (cert, host, port) {
      final h = host.toLowerCase();
      return h == 'fafu.edu.cn' || h.endsWith('.fafu.edu.cn');
    };

    io.connectionFactory = (uri, proxyHost, proxyPort) async {
      Future<InternetAddress> pick(String host) async {
        final addrs = await InternetAddress.lookup(host);
        if (addrs.isEmpty) throw const SocketException('域名解析失败');
        for (final a in addrs) {
          if (a.type == InternetAddressType.IPv4) return a;
        }
        return addrs.first;
      }

      if (proxyHost != null && proxyHost.isNotEmpty) {
        return Socket.startConnect(await pick(proxyHost), proxyPort ?? 8080);
      }
      return Socket.startConnect(await pick(uri.host), uri.port);
    };

    return IOClient(io);
  }

  final http.Client _client = buildClient();
  static const Duration _timeout = Duration(seconds: 25);

  String path = ''; // 会话路径，形如 "(xxxxxxxxxxxxxxxxxxxx)"，**带括号**
  String studentId = '';
  String studentName = '';

  /// 登录页的 __VIEWSTATE。
  ///
  /// 必须与"取验证码"处于**同一个会话**：正方每次访问首页都会新建一个会话，
  /// 验证码也只对生成它的那个会话有效。所以登录页只能加载一次，提交时直接复用，
  /// 绝不能重新拉取——否则用户看到的验证码属于旧会话，必然提示"验证码不正确"。
  String _viewState = '';

  Uri _uri(String page) => Uri.parse('$base/$path/$page');

  /// 从任意 URL 中提取正方会话路径，**连括号一起保存**。
  ///
  /// 正方的无 Cookie 会话在 URL 里必须是 `/(xxxxxxxx)/page.aspx` 这种**带圆括号**
  /// 的形式；去掉括号会变成 `/xxxxxxxx/page.aspx`，服务器找不到会话，返回
  /// 「ERROR - 出错啦！系统正忙！请重新登录」错误页。所以这里务必把括号一起存下来。
  void _syncPathFrom(String url) {
    // 会话 ID 由服务器随机生成，大小写都可能出现，这里不区分大小写
    final m = RegExp(r'\((S?[0-9A-Za-z]{20,})\)').firstMatch(url);
    if (m != null) path = '(${m.group(1)!})';
  }

  /// 手动跟随重定向的 GET。返回 (最终 URL, 响应)。
  Future<(Uri, http.Response)> _getFollowing(
    Uri url, {
    Map<String, String>? extraHeaders,
    int maxHops = 6,
  }) async {
    var current = url;
    for (var hop = 0; hop < maxHops; hop++) {
      final req = http.Request('GET', current)..followRedirects = false;
      req.headers.addAll(_headers);
      if (extraHeaders != null) req.headers.addAll(extraHeaders);

      final resp = await http.Response.fromStream(
        await _client.send(req),
      ).timeout(_timeout);

      _syncPathFrom(current.toString());

      final loc = resp.headers['location'];
      if (resp.statusCode >= 300 &&
          resp.statusCode < 400 &&
          loc != null &&
          loc.isNotEmpty) {
        current = current.resolve(loc);
        continue;
      }
      return (current, resp);
    }
    throw Exception('重定向次数过多，无法打开教务系统页面');
  }

  /// POST 表单；若服务器回 302 则按浏览器行为用 GET 跟随。
  Future<(Uri, http.Response)> _postFollowing(
    Uri url,
    Map<String, String> fields, {
    Map<String, String>? extraHeaders,
    int maxHops = 6,
  }) async {
    final body = fields.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    var current = url;
    var method = 'POST';
    var payload = gbk.encode(body);

    for (var hop = 0; hop < maxHops; hop++) {
      final req = http.Request(method, current)..followRedirects = false;
      req.headers.addAll(_headers);
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded';
      if (extraHeaders != null) req.headers.addAll(extraHeaders);
      if (method == 'POST') req.bodyBytes = payload;

      final resp = await http.Response.fromStream(
        await _client.send(req),
      ).timeout(_timeout);

      _syncPathFrom(current.toString());

      final loc = resp.headers['location'];
      if (resp.statusCode >= 300 &&
          resp.statusCode < 400 &&
          loc != null &&
          loc.isNotEmpty) {
        current = current.resolve(loc);
        // 302 之后浏览器改用 GET，不再带表单
        method = 'GET';
        payload = Uint8List(0);
        continue;
      }
      return (current, resp);
    }
    throw Exception('重定向次数过多');
  }

  String _decode(http.Response r) {
    try {
      return gbk.decode(r.bodyBytes);
    } catch (_) {
      return utf8.decode(r.bodyBytes, allowMalformed: true);
    }
  }

  static String? _viewStateOf(String html) =>
      RegExp(r'name="__VIEWSTATE"\s+value="([^"]*)"').firstMatch(html)?.group(1);

  /// 打开登录页，返回 __VIEWSTATE；同时把会话 ID 记下来。
  Future<String> openLoginPage() async {
    final (finalUri, resp) = await _getFollowing(Uri.parse('$base/'));
    _syncPathFrom(finalUri.toString());

    if (path.isEmpty) {
      // 少数情况下首页不跳转，直接试 default2.aspx
      final (u2, r2) = await _getFollowing(Uri.parse('$base/default2.aspx'));
      _syncPathFrom(u2.toString());
      if (path.isEmpty) {
        throw Exception(
            '已连通教务系统（HTTP ${resp.statusCode}），但未取到会话 ID。\n'
            '若此处是学校的上网认证页面，请先在浏览器完成认证。');
      }
      final vs2 = _viewStateOf(_decode(r2));
      if (vs2 == null) throw Exception('登录页结构异常，可能系统已改版');
      _viewState = vs2;
      return vs2;
    }

    final vs = _viewStateOf(_decode(resp));
    if (vs == null) {
      throw Exception('登录页结构异常，可能系统已改版（HTTP ${resp.statusCode}）');
    }
    _viewState = vs;
    return vs;
  }

  /// 获取验证码图片字节
  Future<Uint8List> fetchCaptcha() async {
    if (path.isEmpty) throw Exception('会话尚未建立，请重新打开登录页');
    final (_, resp) = await _getFollowing(
      _uri('CheckCode.aspx'),
      extraHeaders: {'Referer': _uri('default2.aspx').toString()},
    );
    return resp.bodyBytes;
  }

  /// 提交登录。返回 null 表示成功，否则返回错误提示。
  ///
  /// **不要在这里重新拉登录页**：那会新建一个会话，导致用户刚看到的验证码失效
  /// （现象就是"验证码一直不正确"）。这里只复用调用方已经加载好的会话与 VIEWSTATE。
  Future<String?> submitLogin({
    required String username,
    required String password,
    required String captcha,
  }) async {
    // 只有尚未加载过登录页时才兜底加载一次（正常流程不会走到）
    if (path.isEmpty || _viewState.isEmpty) {
      await openLoginPage();
    }
    if (path.isEmpty) throw Exception('会话尚未建立，请重新打开登录页');

    final (finalUri, resp) = await _postFollowing(
      _uri('default2.aspx'),
      {
        '__VIEWSTATE': _viewState,
        'txtUserName': username,
        'TextBox2': password,
        'txtSecretCode': captcha,
        'RadioButtonList1': '学生',
        'Button1': '',
        'lbLanguage': '',
        'hidPdrs': '',
        'hidsc': '',
      },
      extraHeaders: {'Referer': _uri('default2.aspx').toString()},
    );

    final text = _decode(resp);
    final finalUrl = finalUri.toString();

    if (finalUrl.contains('xs_main.aspx') || text.contains('xs_main.aspx')) {
      studentId = username;
      _absorbName(text);
      return null;
    }

    final alert = RegExp(r"alert\('([^']*)'\)").firstMatch(text) ??
        RegExp(r'alert\("([^"]*)"\)').firstMatch(text);
    return alert?.group(1) ?? '登录失败，请重试';
  }

  void _absorbName(String html) {
    final m = RegExp(r"""[?&]xm=([^&"']+)""").firstMatch(html);
    if (m == null) return;
    try {
      final decoded = Uri.decodeComponent(m.group(1)!);
      if (decoded.isNotEmpty && !decoded.contains('%')) studentName = decoded;
    } catch (_) {}
  }

  /// 抓取课表页面 HTML
  Future<String> fetchSchedulePage({String? xnd, String? xqd}) async {
    if (path.isEmpty) throw Exception('会话已失效，请重新登录');

    final page = 'xskbcx.aspx?xh=$studentId'
        '&xm=${Uri.encodeQueryComponent(studentName)}'
        '&gnmkdm=$gnmkdmKbcx';

    final (_, first) = await _getFollowing(
      _uri(page),
      extraHeaders: {'Referer': _uri('xs_main.aspx?xh=$studentId').toString()},
    );
    var html = _decode(first);

    if (html.contains('name="txtUserName"')) {
      throw Exception('会话已失效，请重新登录');
    }

    // 指定学年/学期时模拟下拉框回发
    if ((xnd != null && xnd.isNotEmpty) || (xqd != null && xqd.isNotEmpty)) {
      final vs = _viewStateOf(html);
      final curXnd = _selectedOption(html, 'xnd');
      final curXqd = _selectedOption(html, 'xqd');
      final (_, second) = await _postFollowing(
        _uri(page),
        {
          '__EVENTTARGET': '',
          '__EVENTARGUMENT': '',
          '__VIEWSTATE': vs ?? '',
          'xnd': (xnd != null && xnd.isNotEmpty) ? xnd : curXnd,
          'xqd': (xqd != null && xqd.isNotEmpty) ? xqd : curXqd,
        },
        extraHeaders: {'Referer': _uri(page).toString()},
      );
      html = _decode(second);
    }
    return html;
  }

  /// 取某个 select 的选中值
  static String _selectedOption(String html, String name) {
    final sel = RegExp('<select[^>]*name="$name"[^>]*>(.*?)</select>',
            caseSensitive: false, dotAll: true)
        .firstMatch(html);
    if (sel == null) return '';
    final body = sel.group(1)!;
    final chosen =
        RegExp(r'<option[^>]*selected[^>]*value="([^"]*)"', caseSensitive: false)
            .firstMatch(body);
    if (chosen != null) return chosen.group(1)!;
    final first = RegExp(r'<option[^>]*value="([^"]*)"', caseSensitive: false)
        .firstMatch(body);
    return first?.group(1) ?? '';
  }

  void close() => _client.close();
}
