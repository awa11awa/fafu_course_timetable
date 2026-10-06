import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 账号密码加密存储（Android Keystore / iOS Keychain）。
///
/// 只存统一身份认证的账号密码，用于会话过期时静默重登。
/// 用户点"退出登录"时清除。
class CredentialStore {
  static const _kUser = 'cas_username';
  static const _kPass = 'cas_password';
  static const _storage = FlutterSecureStorage();

  static Future<bool> get hasCredentials async {
    final u = await _storage.read(key: _kUser);
    final p = await _storage.read(key: _kPass);
    return (u?.isNotEmpty ?? false) && (p?.isNotEmpty ?? false);
  }

  static Future<(String, String)?> read() async {
    final u = await _storage.read(key: _kUser);
    final p = await _storage.read(key: _kPass);
    if (u == null || u.isEmpty || p == null || p.isEmpty) return null;
    return (u, p);
  }

  static Future<void> save(String username, String password) async {
    await _storage.write(key: _kUser, value: username);
    await _storage.write(key: _kPass, value: password);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kUser);
    await _storage.delete(key: _kPass);
  }
}
