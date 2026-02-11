/// 认证 Token 信息
class AuthToken {
  /// Access Token
  final String accessToken;

  /// Token 类型（通常是 "Bearer"）
  final String tokenType;

  /// 创建时间
  final DateTime createdAt;

  AuthToken({
    required this.accessToken,
    this.tokenType = 'Bearer',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 从字符串创建（token 直接是字符串）
  factory AuthToken.fromString(String token) {
    return AuthToken(accessToken: token);
  }

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    DateTime? createdAt;
    if (json['createdAt'] != null) {
      createdAt = DateTime.tryParse(json['createdAt'] as String);
    }
    return AuthToken(
      accessToken: json['accessToken'] as String,
      tokenType: json['tokenType'] as String? ?? 'Bearer',
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'tokenType': tokenType,
        'createdAt': createdAt.toIso8601String(),
      };

  /// 是否已过期
  bool get isExpired => false;
}
