import '../models/token.dart';

/// Standard OAuth2 token endpoint response
class OAuthTokenResponse {
  OAuthTokenResponse({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    this.tokenType = 'Bearer',
    this.expiresIn,
    this.scope,
  });

  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final String tokenType;
  final int? expiresIn;
  final String? scope;

  factory OAuthTokenResponse.fromJson(Map<String, dynamic> json) {
    return OAuthTokenResponse(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      idToken: json['id_token'] as String?,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: json['expires_in'] as int?,
      scope: json['scope'] as String?,
    );
  }

  AuthToken toAuthToken() {
    DateTime? expiresAt;
    if (expiresIn != null && expiresIn! > 0) {
      expiresAt = DateTime.now().add(Duration(seconds: expiresIn!));
    }
    return AuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      tokenType: tokenType,
      expiresAt: expiresAt,
    );
  }
}
