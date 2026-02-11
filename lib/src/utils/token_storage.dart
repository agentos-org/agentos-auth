import 'dart:convert';
import 'dart:io';

import '../models/token.dart';

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

/// Token 存储接口
abstract class TokenStorage {
  /// 保存 Token
  Future<void> saveToken(AuthToken token);

  /// 加载 Token
  Future<AuthToken?> loadToken();

  /// 清除 Token
  Future<void> clearToken();

  /// 是否有保存的 Token
  Future<bool> hasToken();
}

/// 默认实现：使用混淆后的 JSON 文件存储
class DefaultTokenStorage implements TokenStorage {
  DefaultTokenStorage({required this.storagePath});

  /// Token 文件的完整路径
  final String storagePath;

  @override
  Future<void> saveToken(AuthToken token) async {
    final file = File(storagePath);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final plain = jsonEncode(token.toJson());
    await file.writeAsString(_obfuscate(plain));
  }

  @override
  Future<AuthToken?> loadToken() async {
    final file = File(storagePath);
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      if (content.isEmpty) return null;

      final jsonStr = _deobfuscate(content);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AuthToken.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearToken() async {
    final file = File(storagePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> hasToken() async {
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
