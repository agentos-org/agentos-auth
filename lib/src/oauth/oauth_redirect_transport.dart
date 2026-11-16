/// OAuth callback transport
enum OAuthRedirectTransport {
  /// Custom URL scheme (optional, currently disabled by default)
  customScheme,

  /// Loopback HTTP + local HTML success page
  loopback,
}

/// Choose the OAuth callback mode
abstract final class OAuthRedirectTransportResolver {
  /// Use the loopback local HTML callback on all platforms by default
  static OAuthRedirectTransport forPlatform() {
    return OAuthRedirectTransport.loopback;
  }

  static bool get usesCustomScheme =>
      forPlatform() == OAuthRedirectTransport.customScheme;
}
