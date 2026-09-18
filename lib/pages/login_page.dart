import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/network_diag.dart';
import '../services/store.dart';
import '../services/sync_service.dart';
import '../services/zf_client.dart';
import '../theme.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onDone;
  const LoginPage({super.key, required this.onDone});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _idCtrl = TextEditingController(text: Store.studentId);
  final _pwCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  ZfClient? _client;
  Uint8List? _captcha;
  bool _loading = false;
  bool _booting = true;
  String _error = '';
  int _captchaSeq = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _error = '';
    });
    try {
      _client?.close();
      _client = await SyncService.beginLogin();
      _captcha = await SyncService.captcha(_client!);
    } catch (e) {
      // 把真实原因显示出来，便于判断是网络、IPv6 还是学校限制访问
      _error = '无法连接教务系统\n${_brief(e)}\n'
          '· 校内：确认已连接校园网\n'
          '· 校外：把上方「接入地址」切换为「校外 WebVPN」\n'
          '也可点「网络诊断」查看具体卡在哪一步';
    }
    if (mounted) setState(() => _booting = false);
  }

  /// 精简异常文本，避免把整段堆栈糊在界面上
  static String _brief(Object e) {
    var s = e.toString();
    s = s.replaceAll(RegExp(r'^Exception:\s*'), '');
    if (s.length > 220) s = '${s.substring(0, 220)}…';
    return s;
  }

  Future<void> _runDiagnostics() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Text('正在诊断网络…'),
          ],
        ),
      ),
    );

    final steps = await NetworkDiagnostics.run();
    NetworkDiagnostics.log(steps);
    if (!mounted) return;
    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('网络诊断'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              NetworkDiagnostics.format(steps),
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshCaptcha() async {
    if (_client == null) return _boot();
    try {
      final c = await SyncService.captcha(_client!);
      _codeCtrl.clear();
      if (mounted) {
        setState(() {
          _captcha = c;
          _captchaSeq++;
        });
      }
    } catch (_) {}
  }

  Future<void> _login() async {
    final id = _idCtrl.text.trim();
    final pw = _pwCtrl.text;
    final code = _codeCtrl.text.trim();
    if (id.isEmpty || pw.isEmpty) {
      setState(() => _error = '请输入学号与密码');
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final err = await SyncService.submit(_client!,
          studentId: id, password: pw, captcha: code);
      if (err != null) {
        // 失败后整体重来：正方每次访问首页都会新建会话，只换验证码图片
        // 可能与当前会话/VIEWSTATE 对不上，这里连会话一起刷新最稳妥
        await _boot();
        if (mounted) setState(() => _error = err);
        return;
      }
      await SyncService.fetchAndSave(_client!);
      if (mounted) widget.onDone();
    } catch (e) {
      await _boot();
      if (mounted) setState(() => _error = '登录出错：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _client?.close();
    _idCtrl.dispose();
    _pwCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // 顶部蓝色区
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 46,
              bottom: 42,
            ),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(26),
                bottomRight: Radius.circular(26),
              ),
            ),
            child: const Column(
              children: [
                Icon(Icons.calendar_month, color: Colors.white, size: 46),
                SizedBox(height: 12),
                Text('fafu课程表',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                SizedBox(height: 6),
                Text('福建农林大学 · 教务系统课表',
                    style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label('接入地址'),
                  _baseSelector(),
                  const SizedBox(height: 16),
                  _label('学号'),
                  TextField(
                    controller: _idCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '请输入学号'),
                  ),
                  const SizedBox(height: 16),
                  _label('密码'),
                  TextField(
                    controller: _pwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: '请输入教务系统密码'),
                  ),
                  const SizedBox(height: 16),
                  _label('验证码'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeCtrl,
                          onSubmitted: (_) => _login(),
                          decoration: const InputDecoration(
                            hintText: '输入右侧字符',
                            counterText: '',
                          ),
                          maxLength: 6,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _booting ? null : _refreshCaptcha,
                        child: Container(
                          width: 108,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.divider),
                          ),
                          alignment: Alignment.center,
                          child: _bootCaptcha(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('看不清？点击图片换一张',
                      style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F0),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFD6D3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            size: 17, color: Color(0xFFD4380D)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error,
                              style: const TextStyle(
                                  color: Color(0xFFD4380D), fontSize: 13)),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: (_loading || _booting) ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('登 录'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _runDiagnostics,
                        icon: const Icon(Icons.wifi_tethering, size: 17),
                        label: const Text('网络诊断'),
                      ),
                      TextButton.icon(
                        onPressed: _booting ? null : _boot,
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text('重试连接'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '账号密码仅保存在本机，用于自动更新课表',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textFaint),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bootCaptcha() {
    if (_booting) {
      return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_captcha == null) {
      return const Text('获取失败', style: TextStyle(fontSize: 12, color: AppColors.textSub));
    }
    return Image.memory(
      _captcha!,
      key: ValueKey(_captchaSeq),
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
  }

  /// 校内直连 / 校外 WebVPN 切换。
  /// 学校「校外访问教务管理系统」公告给出的地址是
  /// https://jwgl.webvpn.fafu.edu.cn:880/ ，校外网络需要用它。
  Widget _baseSelector() {
    final options = <(String, String)>[
      ('校内直连', Store.baseDirect),
      ('校外 WebVPN', Store.baseWebVpn),
    ];
    final current = Store.baseUrl;
    return Row(
      children: options.map((o) {
        final active = current == o.$2;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: active
                  ? null
                  : () async {
                      await Store.saveBaseUrl(o.$2);
                      await _boot();
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : AppColors.primaryFaint,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: active ? AppColors.primary : AppColors.divider),
                ),
                child: Text(
                  o.$1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? Colors.white : AppColors.textSub,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Text(s,
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSub,
                fontWeight: FontWeight.w500)),
      );
}
