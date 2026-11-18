import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentos_auth/agentos_auth.dart';
import 'package:test/test.dart';

/// In-memory [TokenStorage] so the tests never touch `~/.agentos`.
class _MemoryStorage implements TokenStorage {
  _MemoryStorage([this.session]);

  AuthSession? session;

  @override
  Future<void> saveSession(AuthSession session) async => this.session = session;

  @override
  Future<AuthSession?> loadSession() async => session;

  @override
  Future<void> clearSession() async => session = null;

  @override
  Future<bool> hasSession() async => session != null;
}

/// Tiny token endpoint whose reply is decided by the test.
class _TokenServer {
  _TokenServer._(this._server);

  final HttpServer _server;
  final requests = <String>[];

  int statusCode = 200;
  Object? body = {
    'access_token': 'new-access',
    'refresh_token': 'new-refresh',
    'expires_in': 7200,
  };

  String get address => 'http://127.0.0.1:${_server.port}';

  static Future<_TokenServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final tokenServer = _TokenServer._(server);
    server.listen(tokenServer._handle);
    return tokenServer;
  }

  Future<void> _handle(HttpRequest request) async {
    requests.add('${request.method} ${request.uri.path}');
    await utf8.decoder.bind(request).join();
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

AuthSession _session(String serverAddress, {String? refreshToken = 'old-refresh'}) {
  return AuthSession(
    serverAddress: serverAddress,
    token: AuthToken(accessToken: 'old-access', refreshToken: refreshToken),
  );
}

Future<AuthClient> _signedInClient(
  String serverAddress, {
  String? refreshToken = 'old-refresh',
  _MemoryStorage? storage,
}) async {
  final client = AuthClient(
    tokenStorage:
        storage ?? _MemoryStorage(_session(serverAddress, refreshToken: refreshToken)),
  );
  await client.initialize(serverAddress: serverAddress);
  return client;
}

Future<AuthException> _refreshFailure(AuthClient client) async {
  try {
    await client.refreshToken();
  } on AuthException catch (e) {
    return e;
  }
  fail('refreshToken() should have thrown an AuthException');
}

void main() {
  late _TokenServer server;

  setUp(() async => server = await _TokenServer.start());
  tearDown(() => server.close());

  group('refreshToken success', () {
    test('rotates the tokens and persists the new session', () async {
      final storage = _MemoryStorage(_session(server.address));
      final client = await _signedInClient(server.address, storage: storage);

      final token = await client.refreshToken();

      expect(token.accessToken, 'new-access');
      expect(token.refreshToken, 'new-refresh');
      expect(client.currentToken!.refreshToken, 'new-refresh');
      expect(storage.session!.token.refreshToken, 'new-refresh');
      expect(server.requests, ['POST /agentos-server/oauth2/token']);
    });
  });

  group('refreshToken failures', () {
    test('invalid_grant (HTTP 400) means the user has to sign in again', () async {
      server
        ..statusCode = 400
        ..body = {
          'error': 'invalid_grant',
          'error_description': 'refresh token expired',
        };
      final client = await _signedInClient(server.address);

      final error = await _refreshFailure(client);

      expect(error.type, AuthErrorType.rejected);
      expect(error.requiresLogin, isTrue);
      expect(error.isRetryable, isFalse);
      expect(error.statusCode, 400);
      expect(error.oauthError, 'invalid_grant');
      expect(error.message, contains('refresh token expired'));
    });

    for (final status in [401, 403]) {
      test('HTTP $status is a rejection', () async {
        server
          ..statusCode = status
          ..body = {'error': 'invalid_client'};
        final client = await _signedInClient(server.address);

        final error = await _refreshFailure(client);

        expect(error.type, AuthErrorType.rejected);
        expect(error.requiresLogin, isTrue);
        expect(error.statusCode, status);
      });
    }

    for (final status in [500, 502, 503, 408, 429]) {
      test('HTTP $status is transient and keeps the session usable', () async {
        server
          ..statusCode = status
          ..body = {'msg': 'try later'};
        final client = await _signedInClient(server.address);

        final error = await _refreshFailure(client);

        expect(error.type, AuthErrorType.server);
        expect(error.isRetryable, isTrue);
        expect(error.requiresLogin, isFalse);
        expect(client.isAuthenticated, isTrue);
        expect(client.currentToken!.refreshToken, 'old-refresh');
      });
    }

    test('an unexpected status is neither retryable nor a rejection', () async {
      server
        ..statusCode = 404
        ..body = {'msg': 'gone'};
      final client = await _signedInClient(server.address);

      final error = await _refreshFailure(client);

      expect(error.type, AuthErrorType.unknown);
      expect(error.isRetryable, isFalse);
      expect(error.requiresLogin, isFalse);
    });

    test('a response without access_token is a server problem', () async {
      server.body = {'token_type': 'Bearer'};
      final client = await _signedInClient(server.address);

      final error = await _refreshFailure(client);

      expect(error.type, AuthErrorType.server);
      expect(error.isRetryable, isTrue);
    });

    test('an unreachable server is a network failure', () async {
      final client = await _signedInClient(server.address);
      await server.close();

      final error = await _refreshFailure(client);

      expect(error.type, AuthErrorType.network);
      expect(error.isRetryable, isTrue);
      expect(error.requiresLogin, isFalse);
      expect(client.isAuthenticated, isTrue);
    });

    test('no local session cannot be refreshed', () async {
      final client = AuthClient(tokenStorage: _MemoryStorage());
      await client.initialize(serverAddress: server.address);

      final error = await _refreshFailure(client);

      expect(error.type, AuthErrorType.noSession);
      expect(error.requiresLogin, isTrue);
      expect(server.requests, isEmpty);
    });

    test('a session without refresh token cannot be refreshed', () async {
      final client = await _signedInClient(server.address, refreshToken: null);

      final error = await _refreshFailure(client);

      expect(error.type, AuthErrorType.noSession);
      expect(error.requiresLogin, isTrue);
      expect(server.requests, isEmpty);
    });
  });

  test('toString keeps the plain Exception format', () {
    const error = AuthException('boom', type: AuthErrorType.network);

    expect(error.toString(), 'Exception: boom');
    expect(error, isA<Exception>());
  });
}
