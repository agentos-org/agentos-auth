import 'dart:async';
import 'dart:io';

import 'oauth_config.dart';

/// Loopback 回调模式
enum LoopbackMode {
  /// OAuth 登录：必须有 `code`
  oauthLogin,

  /// 远端登出回跳：任意访问 callback 路径即视为完成
  postLogout,
}

/// 固定端口的 loopback OAuth 回调服务
class LoopbackRedirectServer {
  LoopbackRedirectServer({
    this.host = OAuthDefaults.redirectHost,
    this.port = OAuthDefaults.redirectPort,
    this.callbackPath = OAuthDefaults.redirectPath,
    this.loginSuccessPath = OAuthDefaults.loginSuccessPath,
    this.logoutSuccessPath = OAuthDefaults.logoutSuccessPath,
    this.mode = LoopbackMode.oauthLogin,
  });

  final String host;
  final int port;
  final String callbackPath;
  final String loginSuccessPath;
  final String logoutSuccessPath;
  final LoopbackMode mode;

  HttpServer? _server;
  Completer<Uri>? _callbackCompleter;
  bool _callbackReceived = false;
  Timer? _stopTimer;

  static LoopbackRedirectServer? _portHolder;

  static const Duration defaultStopDelay = Duration(seconds: 5);

  Uri get redirectUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: callbackPath,
      );

  bool get isRunning => _server != null;

  /// 释放固定端口，避免登录/登出流程互相占用 `53682`
  static Future<void> releasePort() async {
    await _portHolder?.stop();
    _portHolder = null;
  }

  Future<void> start() async {
    if (_server != null) {
      return;
    }

    await releasePort();
    _callbackCompleter = Completer<Uri>();
    _callbackReceived = false;
    _server = await HttpServer.bind(host, port, shared: false);
    _server!.listen(_handleRequest);
    _portHolder = this;
  }

  Future<Uri> waitForCallback({
    Duration timeout = const Duration(minutes: 5),
  }) {
    final completer = _callbackCompleter;
    if (completer == null) {
      throw StateError('LoopbackRedirectServer 未启动');
    }
    return completer.future.timeout(timeout);
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;

    if (_portHolder == this) {
      _portHolder = null;
    }

    final server = _server;
    _server = null;
    if (server != null) {
      await server.close();
    }
    final completer = _callbackCompleter;
    _callbackCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        StateError('OAuth 回调服务已关闭'),
      );
    }
  }

  void scheduleStop({Duration delay = defaultStopDelay}) {
    _stopTimer?.cancel();
    _stopTimer = Timer(delay, () {
      unawaited(stop());
    });
  }

  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;

    if (path == loginSuccessPath) {
      _respondSuccessHtml(request, _LoopbackCompletion.login);
      return;
    }
    if (path == logoutSuccessPath) {
      final completer = _callbackCompleter;
      if (mode == LoopbackMode.postLogout &&
          completer != null &&
          !completer.isCompleted) {
        _callbackReceived = true;
        completer.complete(request.uri);
      }
      _respondSuccessHtml(request, _LoopbackCompletion.logout);
      return;
    }
    if (path != callbackPath) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }

    final completer = _callbackCompleter;
    if (completer == null) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..close();
      return;
    }

    final completion = _completionForMode();

    if (completer.isCompleted && _callbackReceived) {
      _redirectToCompletion(request, completion);
      return;
    }

    if (completer.isCompleted) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..close();
      return;
    }

    final error = request.uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      final description =
          request.uri.queryParameters['error_description'] ?? error;
      _respondPlain(request, '操作失败：$description');
      completer.completeError(Exception('OAuth 回调失败: $description'));
      return;
    }

    final code = request.uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      if (mode == LoopbackMode.postLogout) {
        _callbackReceived = true;
        completer.complete(request.uri);
        _redirectToCompletion(request, _LoopbackCompletion.logout);
        return;
      }

      _respondPlain(request, '登录失败：缺少 authorization code');
      completer.completeError(Exception('OAuth 回调缺少 code'));
      return;
    }

    _callbackReceived = true;
    completer.complete(request.uri);
    _redirectToCompletion(request, _LoopbackCompletion.login);
  }

  _LoopbackCompletion _completionForMode() {
    return mode == LoopbackMode.postLogout
        ? _LoopbackCompletion.logout
        : _LoopbackCompletion.login;
  }

  void _redirectToCompletion(
    HttpRequest request,
    _LoopbackCompletion completion,
  ) {
    final location = _completionUri(completion).toString();
    request.response
      ..statusCode = HttpStatus.found
      ..headers.set(HttpHeaders.locationHeader, location)
      ..close();
  }

  Uri _completionUri(_LoopbackCompletion completion) {
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: completion == _LoopbackCompletion.login
          ? loginSuccessPath
          : logoutSuccessPath,
    );
  }

  void _respondSuccessHtml(
    HttpRequest request,
    _LoopbackCompletion completion,
  ) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(_buildCompletionHtml(completion))
      ..close();
  }

  String _buildCompletionHtml(_LoopbackCompletion completion) {
    final title = completion.title;
    final message = completion.message;
    final appDeepLink = OAuthDefaults.foregroundDeepLink;
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #f5f5f7;
      color: #1d1d1f;
      padding: 24px;
    }
    .card {
      width: 100%;
      max-width: 400px;
      background: #fff;
      border-radius: 16px;
      padding: 32px 28px;
      text-align: center;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.08);
    }
    .icon {
      width: 56px;
      height: 56px;
      margin: 0 auto 20px;
      border-radius: 50%;
      background: rgba(0, 122, 255, 0.12);
      color: #007aff;
      font-size: 28px;
      line-height: 56px;
    }
    h1 {
      font-size: 20px;
      font-weight: 600;
      margin-bottom: 8px;
    }
    p {
      font-size: 14px;
      line-height: 1.6;
      color: #6e6e73;
      margin-bottom: 24px;
    }
    button {
      appearance: none;
      border: none;
      border-radius: 999px;
      font-size: 15px;
      font-weight: 500;
      padding: 12px 24px;
      cursor: pointer;
      width: 100%;
    }
    .btn-primary {
      background: #007aff;
      color: #fff;
    }
    .btn-primary:hover { background: #0066d6; }
    .btn-secondary {
      margin-top: 10px;
      background: #fff;
      color: #007aff;
      border: 1px solid #007aff;
    }
    .btn-secondary:hover { background: rgba(0, 122, 255, 0.08); }
    .actions { display: flex; flex-direction: column; gap: 0; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">✓</div>
    <h1>$title</h1>
    <p>$message</p>
    <div class="actions">
      <button type="button" class="btn-primary" id="open-app-btn">返回 AgentOS</button>
      <button type="button" class="btn-secondary" id="close-btn">关闭标签页</button>
    </div>
  </div>
  <script>
    (function () {
      var appDeepLink = '$appDeepLink';
      document.getElementById('open-app-btn').addEventListener('click', function () {
        window.location.href = appDeepLink;
      });
      document.getElementById('close-btn').addEventListener('click', function () {
        window.close();
      });
    })();
  </script>
</body>
</html>''';
  }

  void _respondPlain(HttpRequest request, String message) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.text
      ..write(message)
      ..close();
  }
}

enum _LoopbackCompletion {
  login('登录成功', '授权已完成，请返回 AgentOS Desktop。'),
  logout('登出成功', '您已退出账号，请返回 AgentOS Desktop。');

  const _LoopbackCompletion(this.title, this.message);

  final String title;
  final String message;
}
