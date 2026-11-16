/// Authentication token information
class AuthToken {
  /// Access Token
  final String accessToken;

  /// Refresh token (OAuth2)
  final String? refreshToken;

  /// ID token (OIDC, optional)
  final String? idToken;

  /// Token type (usually "Bearer")
  final String tokenType;

  /// Creation time
  final DateTime createdAt;

  /// Expiration time (converted from OAuth2 expires_in)
  final DateTime? expiresAt;

  AuthToken({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    this.tokenType = 'Bearer',
    DateTime? createdAt,
    this.expiresAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    DateTime? createdAt;
    if (json['createdAt'] != null) {
      createdAt = DateTime.tryParse(json['createdAt'] as String);
    }
    DateTime? expiresAt;
    if (json['expiresAt'] != null) {
      expiresAt = DateTime.tryParse(json['expiresAt'] as String);
    }
    return AuthToken(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      idToken: json['idToken'] as String?,
      tokenType: json['tokenType'] as String? ?? 'Bearer',
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        if (refreshToken != null) 'refreshToken': refreshToken,
        if (idToken != null) 'idToken': idToken,
        'tokenType': tokenType,
        'createdAt': createdAt.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      };

  /// Whether the token has expired (treated as expired 60 seconds early so it can be refreshed proactively)
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(
      expiresAt!.subtract(const Duration(seconds: 60)),
    );
  }

  AuthToken copyWith({
    String? accessToken,
    String? refreshToken,
    String? idToken,
    String? tokenType,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return AuthToken(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      idToken: idToken ?? this.idToken,
      tokenType: tokenType ?? this.tokenType,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
