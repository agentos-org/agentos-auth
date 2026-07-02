import 'oauth_config.dart';

/// 一次 OAuth 登录流程的临时上下文（仅内存保存）
class OAuthLoginSession {
  OAuthLoginSession({
    required this.serverAddress,
    required this.config,
    required this.redirectUri,
    required this.state,
    required this.codeVerifier,
    required this.authorizationUrl,
  });

  final String serverAddress;
  final OAuthConfig config;
  final Uri redirectUri;
  final String state;
  final String codeVerifier;
  final String authorizationUrl;
}
