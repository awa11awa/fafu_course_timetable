import 'dart:io';

import 'package:flutter/foundation.dart';

import 'store.dart';
import 'zf_client.dart';

class DiagStep {
  final String name;
  final bool ok;
  final String detail;
  DiagStep(this.name, this.ok, this.detail);
}

/// 网络自检：把「连不上教务系统」拆成 DNS / TCP 连接 / HTTP 请求三步。
/// 同时测试「校内直连」与学校公告给出的「WebVPN」两个入口，便于判断到底卡在哪。
class NetworkDiagnostics {
  static const List<(String, String)> endpoints = [
    ('校内直连', Store.baseDirect),
    ('WebVPN（校外）', Store.baseWebVpn),
  ];

  static Future<List<DiagStep>> run() async {
    final steps = <DiagStep>[];
    for (final (label, base) in endpoints) {
      steps.addAll(await _probe(label, base));
      steps.add(DiagStep('', true, ''));
    }
    return steps;
  }

  static Future<List<DiagStep>> _probe(String label, String base) async {
    final steps = <DiagStep>[];
    final uri = Uri.parse(base);
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);

    // ---- 1. DNS ----
    List<InternetAddress> addrs;
    final sw = Stopwatch()..start();
    try {
      addrs = await InternetAddress.lookup(host);
      sw.stop();
      final v4 = addrs
          .where((a) => a.type == InternetAddressType.IPv4)
          .map((a) => a.address)
          .toList();
      final v6 = addrs
          .where((a) => a.type == InternetAddressType.IPv6)
          .map((a) => a.address)
          .toList();
      steps.add(DiagStep(
        '$label · 域名解析',
        true,
        '$host · ${sw.elapsedMilliseconds} ms\n'
            'IPv4：${v4.isEmpty ? "无" : v4.join("、")}\n'
            'IPv6：${v6.isEmpty ? "无" : v6.join("、")}',
      ));
    } catch (e) {
      sw.stop();
      steps.add(DiagStep('$label · 域名解析', false, '$host\n$e'));
      return steps;
    }

    // ---- 2. 逐个地址测 TCP 端口 ----
    for (final a in addrs) {
      final tag = a.type == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6';
      final s = Stopwatch()..start();
      try {
        final sock = await Socket.connect(a, port,
            timeout: const Duration(seconds: 6));
        s.stop();
        sock.destroy();
        steps.add(DiagStep('$label · 连接 $tag ${a.address}:$port', true,
            '耗时 ${s.elapsedMilliseconds} ms'));
      } catch (e) {
        s.stop();
        steps.add(DiagStep('$label · 连接 $tag ${a.address}:$port', false,
            '耗时 ${s.elapsedMilliseconds} ms\n$e'));
      }
    }

    // ---- 3. 走一遍真实登录流程（手动跟随重定向、解析会话、取验证码）----
    final client = ZfClient(base: base);
    try {
      final s2 = Stopwatch()..start();
      await client.openLoginPage();
      s2.stop();
      steps.add(DiagStep('$label · 打开登录页', true,
          '会话=${client.path.isEmpty ? "未取到 ✗" : client.path}\n'
          '耗时 ${s2.elapsedMilliseconds} ms · 已取到 __VIEWSTATE'));

      final s3 = Stopwatch()..start();
      final cap = await client.fetchCaptcha();
      s3.stop();
      final sig = cap
          .take(4)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final isGif = sig == '47494638';
      steps.add(DiagStep('$label · 取验证码', isGif,
          'HTTP 200 · ${cap.length} 字节 · 魔数 $sig\n'
          '耗时 ${s3.elapsedMilliseconds} ms · ${isGif ? "GIF 图片，正常" : "不是图片，服务器返回了别的页面"}'));
    } catch (e) {
      steps.add(DiagStep('$label · 登录流程', false, '$e'));
    } finally {
      try {
        client.close();
      } catch (_) {}
    }

    return steps;
  }

  static String format(List<DiagStep> steps) {
    final b = StringBuffer();
    b.writeln('当前接入地址：${Store.baseUrl}\n');
    for (final s in steps) {
      if (s.name.isEmpty) {
        b.writeln('────────────');
        continue;
      }
      b.writeln('${s.ok ? "✅" : "❌"} ${s.name}');
      for (final line in s.detail.split('\n')) {
        b.writeln('    $line');
      }
    }
    return b.toString().trimRight();
  }

  static void log(List<DiagStep> steps) {
    for (final s in steps) {
      if (s.name.isEmpty) continue;
      debugPrint('${s.ok ? "OK " : "FAIL"} ${s.name} :: ${s.detail}');
    }
  }
}
