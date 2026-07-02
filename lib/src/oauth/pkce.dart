import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE 工具（S256）
abstract final class Pkce {
  static final _random = Random.secure();

  /// 生成 code_verifier（43–128 字符）
  static String generateVerifier({int length = 64}) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final clamped = length.clamp(43, 128);
    return List.generate(clamped, (_) => chars[_random.nextInt(chars.length)])
        .join();
  }

  /// 生成随机 state
  static String generateState({int length = 32}) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (_) => chars[_random.nextInt(chars.length)])
        .join();
  }

  /// BASE64URL(SHA256(verifier))，无 padding
  static String challengeS256(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
}
