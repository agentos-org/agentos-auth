/// OAuth 回调承载方式
enum OAuthRedirectTransport {
  /// 自定义 URL Scheme（可选，当前默认未启用）
  customScheme,

  /// Loopback HTTP + 本地 HTML 成功页
  loopback,
}

/// 选择 OAuth 回调方式
abstract final class OAuthRedirectTransportResolver {
  /// 默认全平台使用 loopback 本地 HTML 回调
  static OAuthRedirectTransport forPlatform() {
    return OAuthRedirectTransport.loopback;
  }

  static bool get usesCustomScheme =>
      forPlatform() == OAuthRedirectTransport.customScheme;
}
