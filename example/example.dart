import 'dart:io';

import 'package:agentos_auth/agentos_auth.dart';
import 'package:path/path.dart' as path;

/// Change this to your AgentOS server address (without the `/agentos-server` suffix)
const _serverAddress = 'https://your-server.example.com';

/// Quickly verify OAuth login / refresh / logout locally.
///
/// ```bash
/// cd agentos-auth
/// dart run example/example.dart login
/// dart run example/example.dart refresh
/// dart run example/example.dart status
/// dart run example/example.dart logout
/// dart run example/example.dart full
/// ```
Future<void> main(List<String> args) async {
  final command = args.isNotEmpty ? args.first.toLowerCase() : 'full';

  final sessionPath = path.join(
    Directory.systemTemp.path,
    'agentos-auth-example-session.json',
  );
  print('会话文件: $sessionPath');
  print('服务器: $_serverAddress\n');

  final client = AuthClient(storagePath: sessionPath);
  await client.initialize(serverAddress: _serverAddress);

  switch (command) {
    case 'status':
      _printStatus(client);
      return;
    case 'login':
      await _ensureLoggedIn(client);
      _printStatus(client);
      return;
    case 'refresh':
      await _requireSession(client);
      await _refresh(client);
      _printStatus(client);
      return;
    case 'logout':
      if (!client.isAuthenticated) {
        print('当前未登录，无需登出。');
        return;
      }
      await _logout(client);
      _printStatus(client);
      return;
    case 'full':
      await _runFullFlow(client);
      return;
    default:
      stderr.writeln('未知命令: $command');
      stderr.writeln('可用: login | refresh | logout | status | full');
      exitCode = 64;
  }
}

Future<void> _runFullFlow(AuthClient client) async {
  await _ensureLoggedIn(client);
  _printStatus(client);

  print('\n--- 刷新 access_token ---');
  await _refresh(client);
  _printStatus(client);

  print('\n按 Enter 执行登出（将请求 GET /api/v1/auth/logout + Bearer）...');
  stdin.readLineSync();

  await _logout(client);
  _printStatus(client);
}

Future<void> _ensureLoggedIn(AuthClient client) async {
  if (client.isAuthenticated) {
    print('已存在会话，跳过登录。');
    return;
  }

  print('开始 OAuth 登录，loopback 监听 127.0.0.1:53682 ...');
  final token = await client.loginWithOAuth(
    serverAddress: _serverAddress,
    openAuthorizationUrl: _openAuthorizationUrl,
  );

  print('登录成功。');
  print('access_token 前缀: ${_preview(token.accessToken)}');
  if (token.refreshToken != null) {
    print('refresh_token 前缀: ${_preview(token.refreshToken!)}');
  }
}

Future<void> _requireSession(AuthClient client) async {
  if (client.isAuthenticated) {
    return;
  }
  stderr.writeln('当前未登录。请先: dart run example/example.dart login');
  exit(1);
}

Future<void> _refresh(AuthClient client) async {
  print('请求 POST /oauth2/token (grant_type=refresh_token) ...');
  try {
    final token = await client.refreshToken();
    print('刷新成功。');
    print('新 access_token 前缀: ${_preview(token.accessToken)}');
  } catch (e) {
    print('刷新失败: $e');
    exitCode = 1;
  }
}

Future<void> _logout(AuthClient client) async {
  print('请求远端登出...');
  try {
    await client.logout();
    print('登出成功：服务端已撤销 token，本地会话已清除。');
  } catch (e) {
    print('远端登出失败（本地已清除）: $e');
    exitCode = 1;
  }
}

void _printStatus(AuthClient client) {
  if (!client.isAuthenticated) {
    print('状态: 未登录');
    return;
  }

  final token = client.currentToken!;
  print('状态: 已登录');
  print('server: ${client.currentServerAddress}');
  print('access_token 前缀: ${_preview(token.accessToken)}');
  print(
    'refresh_token 前缀: ${token.refreshToken != null ? _preview(token.refreshToken!) : '(无)'}',
  );
  print('过期时间: ${token.expiresAt}');
  print('是否即将过期: ${token.isExpired}');
}

Future<void> _openAuthorizationUrl(String url) async {
  final opened = await _tryOpenInBrowser(url);
  if (opened) {
    print('已在浏览器打开授权页。');
    return;
  }

  print('无法自动打开浏览器，请手动访问以下链接：');
  print(url);
}

Future<bool> _tryOpenInBrowser(String url) async {
  try {
    if (Platform.isMacOS) {
      final result = await Process.run('open', [url]);
      return result.exitCode == 0;
    }
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [url]);
      return result.exitCode == 0;
    }
    if (Platform.isWindows) {
      final result = await Process.run(
        'cmd',
        ['/c', 'start', '', url],
        runInShell: true,
      );
      return result.exitCode == 0;
    }
  } catch (e) {
    stderr.writeln('打开浏览器失败: $e');
  }
  return false;
}

String _preview(String value, {int length = 12}) {
  if (value.isEmpty) {
    return '(空)';
  }
  if (value.length <= length) {
    return value;
  }
  return '${value.substring(0, length)}...';
}
