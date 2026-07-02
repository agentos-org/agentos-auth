import 'token.dart';

/// 持久化的认证会话
class AuthSession {
  const AuthSession({
    required this.serverAddress,
    required this.token,
  });

  final String serverAddress;
  final AuthToken token;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      serverAddress: json['serverAddress'] as String? ?? '',
      token: AuthToken.fromJson(json['token'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'serverAddress': serverAddress,
        'token': token.toJson(),
      };
}
