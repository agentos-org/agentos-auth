import 'dart:convert';
import 'dart:io';

import '../models/auth_session.dart';

const String _obfuscationKey = 'AgentOS-Auth-Obf-Key';

String _obfuscate(String plain) {
  final keyBytes = _obfuscationKey.codeUnits;
  final data = plain.codeUnits;
  final result = <int>[];
  for (var i = 0; i < data.length; i++) {
    result.add(data[i] ^ keyBytes[i % keyBytes.length]);
  }
  return base64Encode(result);
}

String _deobfuscate(String cipher) {
  final decoded = base64Decode(cipher);
  final keyBytes = _obfuscationKey.codeUnits;
  final result = <int>[];
  for (var i = 0; i < decoded.length; i++) {
    result.add(decoded[i] ^ keyBytes[i % keyBytes.length]);
  }
  return String.fromCharCodes(result);
}

/// 认证会话存储接口
abstract class TokenStorage {
  Future<void> saveSession(AuthSession session);
  Future<AuthSession?> loadSession();
  Future<void> clearSession();
  Future<bool> hasSession();
}

/// 默认实现：混淆 JSON 文件
class DefaultTokenStorage implements TokenStorage {
  DefaultTokenStorage({required this.storagePath});

  final String storagePath;

  @override
  Future<void> saveSession(AuthSession session) async {
    final file = File(storagePath);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final plain = jsonEncode(session.toJson());
    await file.writeAsString(_obfuscate(plain));
  }

  @override
  Future<AuthSession?> loadSession() async {
    final file = File(storagePath);
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      if (content.isEmpty) return null;

      final jsonStr = _deobfuscate(content);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AuthSession.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearSession() async {
    final file = File(storagePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> hasSession() async {
    final file = File(storagePath);
    if (!await file.exists()) return false;

    try {
      final content = await file.readAsString();
      return content.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
