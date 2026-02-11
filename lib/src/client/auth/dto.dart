import '../../models/token.dart';

/// 登录和刷新 Token 的响应
class LoginResponse {
  final AuthToken token;
  final int code;
  final String message;

  LoginResponse({
    required this.token,
    required this.code,
    required this.message,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final tokenString = json['data'] as String? ?? '';
    return LoginResponse(
      token: AuthToken.fromString(tokenString),
      code: json['code'] as int? ?? 0,
      message: json['message'] as String? ?? '',
    );
  }
}

/// 登出响应
class LogoutResponse {
  final int code;
  final String message;
  final String data;

  LogoutResponse({
    required this.code,
    required this.message,
    required this.data,
  });

  factory LogoutResponse.fromJson(Map<String, dynamic> json) {
    return LogoutResponse(
      code: json['code'] as int? ?? 0,
      message: json['message'] as String? ?? '',
      data: json['data'] as String? ?? '',
    );
  }
}
