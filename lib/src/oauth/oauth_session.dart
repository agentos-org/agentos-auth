import 'oauth_config.dart';

/// Temporary context of one OAuth login flow (kept in memory only)
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
