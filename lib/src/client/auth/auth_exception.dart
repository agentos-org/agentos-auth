/// Broad category of a failed auth request.
///
/// It lets callers tell "the credentials are no longer valid" (the user has to sign in again)
/// apart from "the server could not be reached right now" (keep the session and retry later).
enum AuthErrorType {
  /// The server could not be reached: no connection, DNS or TLS failure.
  network,

  /// The connection, send or receive timed out.
  timeout,

  /// The server answered with a transient failure (HTTP 5xx, 408 or 429).
  server,

  /// The server rejected the credentials or the request (HTTP 400, 401 or 403), e.g. OAuth2
  /// `invalid_grant` for a refresh token that is expired, revoked or already rotated.
  rejected,

  /// There is no local session, or it has no refresh token, so nothing can be refreshed.
  noSession,

  /// Anything that does not fit the categories above.
  unknown,
}

/// Failure of a request made by [AuthClient].
///
/// [toString] keeps the `Exception: <message>` form of the plain exceptions thrown before this
/// type existed, so code that only displays the error is unaffected.
class AuthException implements Exception {
  const AuthException(
    this.message, {
    this.type = AuthErrorType.unknown,
    this.statusCode,
    this.oauthError,
  });

  /// Human readable description.
  final String message;

  /// Broad category, see [AuthErrorType].
  final AuthErrorType type;

  /// HTTP status of the response, when the server answered.
  final int? statusCode;

  /// OAuth2 `error` code from the response body (for example `invalid_grant`), when present.
  final String? oauthError;

  /// Whether the failure is probably temporary: the same request may succeed later without the
  /// user doing anything, so the session must not be discarded.
  bool get isRetryable =>
      type == AuthErrorType.network ||
      type == AuthErrorType.timeout ||
      type == AuthErrorType.server;

  /// Whether the session is definitely unusable and the user has to sign in again.
  bool get requiresLogin =>
      type == AuthErrorType.rejected || type == AuthErrorType.noSession;

  @override
  String toString() => 'Exception: $message';
}
