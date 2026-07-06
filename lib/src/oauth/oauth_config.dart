import 'oauth_redirect_transport.dart';

/// OAuth2 客户端配置（对齐 agentos-server oauth2-develop-guide）
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
    this.logoutPath = OAuthDefaults.logoutPath,
    this.revokePath = OAuthDefaults.revokePath,
    this.authorizationPrompt = OAuthDefaults.authorizationPrompt,
    this.redirectTransport,
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
  final String logoutPath;
  final String revokePath;

  /// OIDC `prompt`，桌面端默认 `login` 避免 SSO 静默登录却不回跳
  final String? authorizationPrompt;

  /// 指定回调方式；默认按当前平台自动选择
  final OAuthRedirectTransport? redirectTransport;

  OAuthRedirectTransport get resolvedRedirectTransport =>
      redirectTransport ?? OAuthRedirectTransportResolver.forPlatform();

  /// 当前平台使用的 OAuth redirect_uri
  Uri get redirectUri => redirectUriFor(resolvedRedirectTransport);

  /// 远端登出回跳地址（与 [redirectUri] 同平台策略）
  Uri get postLogoutRedirectUri =>
      postLogoutRedirectUriFor(resolvedRedirectTransport);

  /// Loopback redirect_uri（Linux）
  Uri get loopbackRedirectUri => Uri(
        scheme: 'http',
        host: redirectHost,
        port: redirectPort,
        path: redirectPath,
      );

  /// 自定义 Scheme 登录回调（macOS / Windows）`agentos://oauth/callback`
  Uri get schemeRedirectUri => Uri(
        scheme: customScheme,
        host: schemeHost,
        path: schemeCallbackPath,
      );

  /// 自定义 Scheme 登录完成唤起应用 `agentos://oauth/login/success`
  Uri get schemeLoginSuccessUri => Uri(
        scheme: customScheme,
        host: schemeHost,
        path: schemeLoginSuccessPath,
      );

  /// 自定义 Scheme 登出成功回跳 `agentos://oauth/logout/success`
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

  /// 判断 URI 是否为 OAuth 登录回调
  bool matchesOAuthCallback(Uri uri) {
    final expected = redirectUri;
    return _sameRedirectTarget(uri, expected);
  }

  /// 判断 URI 是否为唤起 Desktop（loopback 成功页「返回 AgentOS」）
  bool matchesForegroundLink(Uri uri) {
    return _sameRedirectTarget(uri, OAuthDefaults.foregroundUri);
  }

  /// 判断 URI 是否为 OAuth 登出回跳
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

/// 去掉首尾空白与末尾斜杠。
String trimServerAddress(String serverAddress) {
  var normalized = serverAddress.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// 远端 API 根地址：`{域名}/agentos-server`。
String serverApiBase(String serverAddress) =>
    '${trimServerAddress(serverAddress)}${OAuthDefaults.serverApiPrefix}';

/// AgentOS Desktop OAuth2 默认值
abstract final class OAuthDefaults {
  /// 远端 API 统一前缀（对齐 agentos-server 网关 context-path）
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

  /// 从浏览器成功页唤起 Desktop（登录 / 登出共用）
  static const String foregroundHost = 'open';

  static Uri get foregroundUri => Uri(scheme: customScheme, host: foregroundHost);

  static String get foregroundDeepLink => foregroundUri.toString();

  /// Loopback 浏览器展示用完成页（无敏感 query 参数）
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
  static const String revokePath = '/oauth2/revoke';

  static const String userInfoPath = '/api/v1/auth/user/info';
  static const String logoutPath = '/api/v1/auth/logout';

  /// 每次授权都要求重新认证，避免浏览器 SSO 会话导致只登录不回跳
  static const String authorizationPrompt = 'login';
}
