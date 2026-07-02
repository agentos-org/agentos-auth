import 'dart:async';

/// 自定义 Scheme 回调通道（由桌面端注入，如 `agentos://oauth/callback`）
abstract class OAuthRedirectHandler {
  /// 等待浏览器回跳到已注册的 redirect_uri
  Future<Uri> waitForRedirect({required Duration timeout});

  /// 取消等待（如用户关闭登录弹窗）
  Future<void> cancel();
}

/// 内存实现，供测试或示例使用
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

  /// 模拟系统唤起应用并传入回调 URI
  void deliver(Uri uri) {
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    completer.complete(uri);
  }
}
