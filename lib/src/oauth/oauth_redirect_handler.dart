import 'dart:async';

/// Custom-scheme callback channel (injected by the desktop app, e.g. `agentos://oauth/callback`)
abstract class OAuthRedirectHandler {
  /// Wait for the browser to redirect back to the registered redirect_uri
  Future<Uri> waitForRedirect({required Duration timeout});

  /// Cancel waiting (e.g. the user closed the login dialog)
  Future<void> cancel();
}

/// In-memory implementation for tests or examples
class InMemoryOAuthRedirectHandler implements OAuthRedirectHandler {
  Completer<Uri>? _completer;
  Timer? _timeoutTimer;

  @override
  Future<void> cancel() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final completer = _completer;
    _completer = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        StateError('OAuth redirect wait cancelled'),
      );
    }
  }

  @override
  Future<Uri> waitForRedirect({required Duration timeout}) {
    unawaited(cancel());
    _completer = Completer<Uri>();
    _timeoutTimer = Timer(timeout, () {
      final completer = _completer;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(TimeoutException('OAuth redirect timeout'));
      }
    });
    return _completer!.future;
  }

  /// Simulate the system launching the app with the callback URI
  void deliver(Uri uri) {
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    completer.complete(uri);
  }
}
