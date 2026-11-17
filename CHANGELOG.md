## 1.0.0

- First release on pub.dev.
- Authorization Code + PKCE (S256) sign-in with a loopback redirect server and
  built-in HTML success pages, plus an optional custom-scheme redirect handler.
- Device Code flow (RFC 8628) for clients without a fixed `redirect_uri`.
- Token refresh, server-side sign-out (`logout()`) and local-only sign-out
  (`logoutLocal()`).
- Session persistence with a default JSON file store and a pluggable
  `TokenStorage` abstraction.
- Support for certificate overrides on OAuth requests.
