import 'oauth_redirect_transport.dart';

/// OAuth2 client configuration (aligned with the agentos-server oauth2-develop-guide)
class OAuthConfig {
  const OAuthConfig({
    this.clientId = OAuthDefaults.clientId,
    this.redirectHost = OAuthDefaults.redirectHost,
    this.redirectPort = OAuthDefaults.redirectPort,
    this.redirectPath = OAuthDefaults.redirectPath,
    this.customScheme = OAuthDefaults.customScheme,
    this.schemeHost = OAuthDefaults.schemeHost,
    this.schemeCallbackPath = OAuthDefaults.schemeCallbackPath,
    this.schemeLoginSuccessPath = OAuthDefaults.schemeLoginSuccessPath,
    this.schemeLogoutSuccessPath = OAuthDefaults.schemeLogoutSuccessPath,
    this.scopes = OAuthDefaults.scopes,
    this.authorizePath = OAuthDefaults.authorizePath,
    this.tokenPath = OAuthDefaults.tokenPath,
    this.deviceAuthorizationPath = OAuthDefaults.deviceAuthorizationPath,
    this.logoutPath = OAuthDefaults.logoutPath,
    this.revokePath = OAuthDefaults.revokePath,
    this.authorizationPrompt = OAuthDefaults.authorizationPrompt,
    this.redirectTransport,
    this.redirectUriOverride,
  });

  final String clientId;
  final String redirectHost;
  final int redirectPort;
  final String redirectPath;
  final String customScheme;
  final String schemeHost;
  final String schemeCallbackPath;
  final String schemeLoginSuccessPath;
  final String schemeLogoutSuccessPath;
  final List<String> scopes;
  final String authorizePath;
  final String tokenPath;
  final String deviceAuthorizationPath;
  final String logoutPath;
  final String revokePath;

  /// OIDC `prompt`; defaults to `login` on desktop to avoid a silent SSO login that never redirects back
  final String? authorizationPrompt;

  /// Specifies the callback mode; by default it is chosen automatically for the current platform
  final OAuthRedirectTransport? redirectTransport;

  /// Fixed redirect_uri used by scenarios such as WebShell (must be registered in the auth center beforehand)
  final Uri? redirectUriOverride;

  OAuthRedirectTransport get resolvedRedirectTransport =>
      redirectTransport ?? OAuthRedirectTransportResolver.forPlatform();

  /// OAuth redirect_uri used on the current platform
  Uri get redirectUri =>
      redirectUriOverride ?? redirectUriFor(resolvedRedirectTransport);

  /// Redirect address after remote logout (same platform strategy as [redirectUri])
  Uri get postLogoutRedirectUri =>
      postLogoutRedirectUriFor(resolvedRedirectTransport);

  /// Loopback redirect_uri (Linux)
  Uri get loopbackRedirectUri => Uri(
        scheme: 'http',
        host: redirectHost,
        port: redirectPort,
        path: redirectPath,
      );

  /// Custom-scheme login callback (macOS / Windows) `agentos://oauth/callback`
  Uri get schemeRedirectUri => Uri(
        scheme: customScheme,
        host: schemeHost,
        path: schemeCallbackPath,
      );

  /// Custom scheme used to wake the app after login completes `agentos://oauth/login/success`
  Uri get schemeLoginSuccessUri => Uri(
        scheme: customScheme,
        host: schemeHost,
        path: schemeLoginSuccessPath,
      );

  /// Custom-scheme redirect after a successful logout `agentos://oauth/logout/success`
  Uri get schemeLogoutSuccessUri => Uri(
        scheme: customScheme,
        host: schemeHost,
        path: schemeLogoutSuccessPath,
      );

  Uri redirectUriFor(OAuthRedirectTransport transport) {
    switch (transport) {
      case OAuthRedirectTransport.customScheme:
        return schemeRedirectUri;
      case OAuthRedirectTransport.loopback:
        return loopbackRedirectUri;
    }
  }

  Uri postLogoutRedirectUriFor(OAuthRedirectTransport transport) {
    switch (transport) {
      case OAuthRedirectTransport.customScheme:
        return schemeLogoutSuccessUri;
      case OAuthRedirectTransport.loopback:
        return Uri(
          scheme: 'http',
          host: redirectHost,
          port: redirectPort,
          path: OAuthDefaults.logoutSuccessPath,
        );
    }
  }

  /// Whether the URI is an OAuth login callback
  bool matchesOAuthCallback(Uri uri) {
    final expected = redirectUri;
    return _sameRedirectTarget(uri, expected);
  }

  /// Whether the URI is used to wake Desktop (the "Back to AgentOS" action on the loopback success page)
  bool matchesForegroundLink(Uri uri) {
    return _sameRedirectTarget(uri, OAuthDefaults.foregroundUri);
  }

  /// Whether the URI is an OAuth logout redirect
  bool matchesOAuthLogoutSuccess(Uri uri) {
    final expected = postLogoutRedirectUri;
    return _sameRedirectTarget(uri, expected);
  }

  bool _sameRedirectTarget(Uri actual, Uri expected) {
    return actual.scheme.toLowerCase() == expected.scheme.toLowerCase() &&
        actual.host.toLowerCase() == expected.host.toLowerCase() &&
        actual.port == expected.port &&
        _normalizePath(actual.path) == _normalizePath(expected.path);
  }

  String _normalizePath(String path) {
    if (path.isEmpty) return '/';
    return path.startsWith('/') ? path : '/$path';
  }

  String get scope => scopes.join(' ');
}

/// Trim leading/trailing whitespace and trailing slashes.
String trimServerAddress(String serverAddress) {
  var normalized = serverAddress.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// Remote API root address: `{domain}/agentos-server`.
String serverApiBase(String serverAddress) =>
    '${trimServerAddress(serverAddress)}${OAuthDefaults.serverApiPrefix}';

/// AgentOS Desktop OAuth2 defaults
abstract final class OAuthDefaults {
  /// Common prefix of the remote API (aligned with the agentos-server gateway context-path)
  static const String serverApiPrefix = '/agentos-server';

  static const String clientId = 'agentos-desktop';

  static const String redirectHost = '127.0.0.1';
  static const int redirectPort = 53682;
  static const String redirectPath = '/oauth/callback';

  static const String customScheme = 'agentos';
  static const String schemeHost = 'oauth';
  static const String schemeCallbackPath = '/callback';
  static const String schemeLoginSuccessPath = '/login/success';
  static const String schemeLogoutSuccessPath = '/logout/success';

  /// Wake Desktop from the browser success page (shared by login / logout)
  static const String foregroundHost = 'open';

  static Uri get foregroundUri => Uri(scheme: customScheme, host: foregroundHost);

  static String get foregroundDeepLink => foregroundUri.toString();

  /// Completion page shown in the loopback browser (no sensitive query parameters)
  static const String loginSuccessPath = '/oauth/login/success';
  static const String logoutSuccessPath = '/oauth/logout/success';

  static const List<String> scopes = [
    'openid',
    'profile',
    'email',
    'phone',
    'agentos.read',
    'agentos.write',
  ];

  static const String authorizePath = '/oauth2/authorize';
  static const String tokenPath = '/oauth2/token';
  static const String deviceAuthorizationPath = '/oauth2/device_authorization';
  static const String revokePath = '/oauth2/revoke';

  static const String userInfoPath = '/api/v1/auth/user/info';
  static const String logoutPath = '/api/v1/auth/logout';

  /// Require re-authentication on every authorization, so a browser SSO session cannot cause a login without a redirect back
  static const String authorizationPrompt = 'login';
}
