import 'package:flutter/material.dart';

import '../services/store.dart';

Future<bool> requestCasHttpConsent(BuildContext context) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('允许自动恢复学校登录'),
      content: const Text('学校认证使用未加密的 HTTP 连接。恢复登录时会向 '
          'auth.fafu.edu.cn 发送保存的登录 Cookie，网络途中的设备可能读取或修改它。'
          '\n\n课表和令牌接口仍使用 HTTPS。开启后可在设置里关闭。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('暂不开启')),
        TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('允许恢复')),
      ],
    ),
  );
  if (approved != true) return false;
  await Store.saveCasHttpAllowed(true);
  return true;
}
