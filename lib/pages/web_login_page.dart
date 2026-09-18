import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/course.dart';
import '../services/store.dart';
import '../services/timetable_api.dart';
import '../theme.dart';

class WebLoginPage extends StatefulWidget {
  final void Function(Schedule schedule) onImported;

  const WebLoginPage({super.key, required this.onImported});

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  late final WebViewController _controller;
  String _url = TimetableApi.timetablePage;
  bool _busy = false;
  int _msgSeq = 0;
  final Map<int, Completer<String>> _pending = {};
  String _hint = '请完成统一身份认证：滑块验证 + 短信验证码';

  bool get _onTimetable =>
      _url.contains('task.fafu.edu.cn') && !_url.contains('authserver');

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('DshBridge', onMessageReceived: (m) {
        Map<String, dynamic>? j;
        try {
          j = jsonDecode(m.message) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        final id = j['id'];
        if (id is! int) return;
        final c = _pending.remove(id);
        if (c != null && !c.isCompleted) c.complete(m.message);
      })
      // 课表要移动端才看得到
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (u) => setState(() => _url = u),
        onPageFinished: (u) => setState(() {
          _url = u;
          _hint = _onTimetable
              ? '已登录。点下方「导入课表」即可同步到本机'
              : '请完成统一身份认证：滑块验证 + 短信验证码';
        }),
      ))
      // 直接打开「我的课表」，未登录会自动跳统一身份认证；
      // 登录后回到课表页，此时即可取数据。
      ..loadRequest(Uri.parse(TimetableApi.timetablePage));
  }

  // ------------------------------------------------------------ 网页交互

  /// 在网页里跑一段 JS，等它用 DshBridge 把 JSON 回传（会自动带上消息 id）。
  Future<Map<String, dynamic>> _eval(String body,
      {int timeoutSec = 25}) async {
    final id = ++_msgSeq;
    final c = Completer<String>();
    _pending[id] = c;
    try {
      await _controller.runJavaScript(
        '(function(){var __id=$id;try{$body}'
        'catch(e){DshBridge.postMessage(JSON.stringify({id:__id,err:String(e)}));}})()',
      );
    } catch (e) {
      _pending.remove(id);
      return {'err': '$e'};
    }
    String raw = '';
    try {
      raw = await c.future.timeout(Duration(seconds: timeoutSec));
    } on TimeoutException {
      raw = '';
    } finally {
      _pending.remove(id);
    }
    if (raw.isEmpty) return {'err': '网页无响应（超时 ${timeoutSec}s）'};
    try {
      final j = jsonDecode(raw);
      if (j is Map) return j.cast<String, dynamic>();
      return {'err': '网页返回格式异常'};
    } catch (_) {
      return {'err': '网页返回无法解析'};
    }
  }

  static const String _jsToken = r'''
fetch('/api8/api/he/token', {credentials:'include',
    headers:{'Accept':'application/json, text/plain, */*'}})
  .then(function(r){ return r.text().then(function(t){
    DshBridge.postMessage(JSON.stringify({id:__id, status:r.status,
      ct:(r.headers.get('content-type')||''), url:r.url, body:t})); }); })
  .catch(function(e){ DshBridge.postMessage(JSON.stringify({id:__id, err:String(e)})); });
''';

  static const String _jsCookie = r'''
DshBridge.postMessage(JSON.stringify({id:__id, cookie:(document.cookie||'')}));
''';

  /// 取登录会话 Cookie。
  ///
  /// 关键点：课表网关只认 CAS 会话 Cookie（NGXCAS），而它往往是 HttpOnly 的，
  /// `document.cookie` 看不到 → 必须用平台 CookieManager 读。
  /// 两条路都走，以 `document.cookie` 的值（最精确）覆盖同名项。
  Future<String> _readCookie() async {
    final out = <String, String>{};
    for (final u in const [
      TimetableApi.timetablePage,
      'https://ehall.fafu.edu.cn/',
      'https://auth.fafu.edu.cn/',
    ]) {
      try {
        final list =
            await WebViewCookieManager().getCookies(domain: Uri.parse(u));
        for (final c in list) {
          if (c.name.isEmpty || c.value.isEmpty) continue;
          out.putIfAbsent(c.name, () => c.value);
        }
        if (out.containsKey(TimetableApi.gatewayCookie)) break;
      } catch (_) {}
    }
    final env = await _eval(_jsCookie, timeoutSec: 8);
    final raw = '${env['cookie'] ?? ''}';
    for (final pair in raw.split(';')) {
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      out[pair.substring(0, i).trim()] = pair.substring(i + 1).trim();
    }
    return out.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 换 JWT：先用本机直连（后台任务也是这条路），失败再退回网页里 fetch。
  Future<String> _getToken(String cookie) async {
    String err1 = '';
    try {
      return await TimetableApi.fetchTokenWithCookie(cookie);
    } catch (e) {
      err1 = '$e';
    }
    final env = await _eval(_jsToken, timeoutSec: 25);
    if (env['err'] != null) {
      throw Exception('$err1；网页内获取也失败：${env['err']}');
    }
    final body = '${env['body'] ?? ''}';
    final t = TimetableApi.tokenOf(body);
    if (t == null) {
      throw Exception('$err1；网页内返回 HTTP ${env['status']}：'
          '${TimetableApi.snippet(body)}');
    }
    return t;
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _hint = '正在读取登录会话…';
    });
    try {
      if (_url.contains('authserver')) {
        throw Exception('还没完成统一身份认证，请先完成滑块验证和短信验证码');
      }
      final cookie = await _readCookie();
      if (!cookie.contains('${TimetableApi.gatewayCookie}=')) {
        throw Exception('没有检测到登录会话，请确认上方网页已经进入「我的课表」'
            '（不是登录页）后再点导入。当前页面：$_url');
      }

      setState(() => _hint = '正在换取登录凭据…');
      final token = await _getToken(cookie);

      final api = TimetableApi(token: token, cookie: cookie);
      setState(() => _hint = '正在读取教学周信息…');
      final info = await api.weekInfo();

      setState(() => _hint = '正在同步整学期课表（约需十几秒）…');
      final courses = await api.fetchSemester(onProgress: (d, t) {
        if (mounted) setState(() => _hint = '正在同步课表 $d/$t …');
      });
      if (courses.isEmpty) {
        setState(() => _hint = '没有读到课程。请确认上方页面已显示课表，再试一次');
        return;
      }

      // 用接口给的开学日期/当前周次校准（自动，无需用户设置）
      await Store.applyWeekInfo(info.weekIndex, info.termStartDate);
      await Store.saveToken(token);
      await Store.saveCookie(cookie);

      final s = Schedule(
        studentId: Store.studentId,
        studentName: TimetableApi.jwtField(token, 'user_name').isNotEmpty
            ? TimetableApi.jwtField(token, 'user_name')
            : (Store.schedule?.studentName ?? ""),
        year: info.schoolYear,
        term: info.semester,
        fetchedAt: DateTime.now(),
        courses: courses,
      );
      await Store.saveSchedule(s);
      if (!mounted) return;
      widget.onImported(s);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _hint = '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _diagnostics() async {
    final sb = StringBuffer();
    sb.writeln('页面：$_url');
    try {
      final cookie = await _readCookie();
      final has = cookie.contains('${TimetableApi.gatewayCookie}=');
      sb.writeln('CAS 会话 Cookie(${TimetableApi.gatewayCookie})：'
          '${has ? '已获取' : '未获取'}（共 ${cookie.length} 字符）');
      if (cookie.isEmpty) {
        sb.writeln('Cookie 明细：无');
      } else {
        sb.writeln('Cookie 明细：${cookie.split('; ').map((e) => e.split('=').first).join(', ')}');
      }
      final env = await _eval(_jsToken, timeoutSec: 20);
      if (env['err'] != null) {
        sb.writeln('网页内 /he/token：${env['err']}');
      } else {
        sb.writeln('网页内 /he/token：HTTP ${env['status']} ${env['ct']}');
        sb.writeln(
            '返回开头：${TimetableApi.snippet('${env['body'] ?? ''}')}');
      }
    } catch (e) {
      sb.writeln('诊断出错：$e');
    }
    final text = sb.toString();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('诊断'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
            },
            child: const Text('复制'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统一身份认证登录'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _diagnostics,
            child: const Text('诊断',
                style: TextStyle(color: Colors.white, fontSize: 14)),
          ),
          IconButton(
            tooltip: '回到课表首页',
            onPressed: () =>
                _controller.loadRequest(Uri.parse(TimetableApi.timetablePage)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Column(
              children: [
                Row(children: [
                  Icon(_onTimetable ? Icons.check_circle_outline : Icons.lock_outline,
                      size: 16,
                      color: _onTimetable ? AppColors.success : AppColors.textFaint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_hint,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSub, height: 1.4)),
                  ),
                ]),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_outlined, size: 18),
                  label: Text(_busy ? '正在导入…' : '导入课表'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
