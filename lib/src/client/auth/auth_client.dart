import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as path;

import '../../models/auth_session.dart';
import '../../models/token.dart';
import '../../oauth/loopback_redirect_server.dart';
import '../../oauth/oauth_config.dart';
import '../../oauth/oauth_device_code.dart';
import '../../oauth/oauth_redirect_handler.dart';
import '../../oauth/oauth_redirect_transport.dart';
import '../../oauth/oauth_session.dart';
import '../../oauth/oauth_token_response.dart';
import '../../oauth/pkce.dart';
import '../../utils/api_client.dart';
import '../../utils/token_storage.dart';

String _getDefaultTokenStoragePath() {
  final homeDir = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Platform.environment['APPDATA'] ??
      '';
  return path.join(homeDir, '.agentos', 'auth', 'session.json');
}

String _normalizeServerAddress(String serverAddress) =>
    trimServerAddress(serverAddress);

/// OAuth2 authentication client (Authorization Code + PKCE / Device Code)
class AuthClient {
  AuthClient({
    ApiClient? apiClient,
    TokenStorage? tokenStorage,
    String? storagePath,
    bool Function(X509Certificate certificate, String host, int port)?
        badCertificateCallback,
  })  : _apiClient = apiClient ?? ApiClient(),
        _tokenStorage = tokenStorage ??
            DefaultTokenStorage(
              storagePath: storagePath ?? _getDefaultTokenStoragePath(),
            ),
        _badCertificateCallback = badCertificateCallback;

  final ApiClient _apiClient;
  final TokenStorage? _tokenStorage;
  final bool Function(X509Certificate certificate, String host, int port)?
      _badCertificateCallback;

  AuthToken? _currentToken;
  String? _currentServerAddress;
  LoopbackRedirectServer? _activeOAuthLoginLoopback;
  OAuthRedirectHandler? _activeOAuthRedirectHandler;
  bool _oauthLoginCancelled = false;

  AuthToken? get currentToken => _currentToken;
  String? get currentServerAddress => _currentServerAddress;
  bool get isAuthenticated =>
      _currentToken != null && _currentServerAddress != null;

  /// Restore the session from local storage
  Future<void> initialize({String? serverAddress}) async {
    final session = await _tokenStorage?.loadSession();
    if (session != null) {
      _applySession(session);
      return;
    }

    if (serverAddress != null) {
      _currentServerAddress = _normalizeServerAddress(serverAddress);
    }
  }

  /// Prepare the OAuth authorization (generates PKCE / state / authorization URL)
  OAuthLoginSession beginOAuthLogin({
    required String serverAddress,
    OAuthConfig config = const OAuthConfig(),
  }) {
    final normalizedServer = _normalizeServerAddress(serverAddress);
    final redirectUri = config.redirectUri;
    final state = Pkce.generateState();
    final codeVerifier = Pkce.generateVerifier();
    final codeChallenge = Pkce.challengeS256(codeVerifier);

    final authorizationUrl = Uri.parse(
      '${serverApiBase(normalizedServer)}${config.authorizePath}',
    ).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': config.clientId,
        'redirect_uri': redirectUri.toString(),
        'scope': config.scope,
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        if (config.authorizationPrompt != null &&
            config.authorizationPrompt!.isNotEmpty)
          'prompt': config.authorizationPrompt!,
      },
    ).toString();

    return OAuthLoginSession(
      serverAddress: normalizedServer,
      config: config,
      redirectUri: redirectUri,
      state: state,
      codeVerifier: codeVerifier,
      authorizationUrl: authorizationUrl,
    );
  }

  /// Handle the loopback callback and exchange it for a token
  Future<AuthToken> completeOAuthLogin({
    required OAuthLoginSession session,
    required Uri callbackUri,
  }) async {
    final returnedState = callbackUri.queryParameters['state'];
    if (returnedState != session.state) {
      throw Exception('OAuth state 校验失败');
    }

    final code = callbackUri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('OAuth 回调缺少 authorization code');
    }

    final token = await _exchangeAuthorizationCode(
      serverAddress: session.serverAddress,
      config: session.config,
      code: code,
      redirectUri: session.redirectUri,
      codeVerifier: session.codeVerifier,
    );

    await _persistSession(
      AuthSession(serverAddress: session.serverAddress, token: token),
    );
    return token;
  }

  /// Cancel an in-progress OAuth login
  Future<void> cancelOAuthLogin() async {
    _oauthLoginCancelled = true;
    final handler = _activeOAuthRedirectHandler;
    _activeOAuthRedirectHandler = null;
    await handler?.cancel();

    final loopback = _activeOAuthLoginLoopback;
    _activeOAuthLoginLoopback = null;
    await loopback?.stop();
    await LoopbackRedirectServer.releasePort();
  }

  /// Start Device Code authorization (RFC 8628)
  ///
  /// `scope` is not sent by default, so the auth center applies the permissions registered for the client;
  /// set [includeScope] to true when the scope must be requested explicitly.
  Future<DeviceCodeSession> beginDeviceCodeLogin({
    required String serverAddress,
    OAuthConfig config = const OAuthConfig(),
    bool includeScope = false,
  }) async {
    final normalizedServer = _normalizeServerAddress(serverAddress);

    try {
      final dio = _createDio(BaseOptions(
        baseUrl: serverApiBase(normalizedServer),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          Headers.contentTypeHeader: Headers.formUrlEncodedContentType,
        },
      ));

      final response = await dio.post(
        config.deviceAuthorizationPath,
        data: {
          'client_id': config.clientId,
          if (includeScope) 'scope': config.scope,
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Device authorization 响应无效');
      }

      final deviceCode = data['device_code'] as String? ?? '';
      if (deviceCode.isEmpty) {
        throw Exception('Device authorization 响应缺少 device_code');
      }

      return DeviceCodeSession(
        serverAddress: normalizedServer,
        config: config,
        deviceCode: deviceCode,
        userCode: data['user_code'] as String? ?? '',
        verificationUri: data['verification_uri'] as String? ?? '',
        verificationUriComplete:
            data['verification_uri_complete'] as String? ?? '',
        expiresIn: data['expires_in'] as int? ?? 600,
        interval: data['interval'] as int? ?? 5,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Poll the Device Code authorization status; the session is persisted on success
  Future<DeviceCodePollResult> pollDeviceCode({
    required DeviceCodeSession session,
  }) async {
    if (session.isExpired) {
      return DeviceCodePollResult.expired('Device code expired');
    }

    try {
      final dio = _createDio(BaseOptions(
        baseUrl: serverApiBase(session.serverAddress),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          Headers.contentTypeHeader: Headers.formUrlEncodedContentType,
        },
        validateStatus: (status) => status != null && status < 500,
      ));

      final response = await dio.post(
        session.config.tokenPath,
        data: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'client_id': session.config.clientId,
          'device_code': session.deviceCode,
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return DeviceCodePollResult.error('Invalid token response');
      }

      if (response.statusCode == 400) {
        final error = data['error'] as String? ?? '';
        if (error == 'authorization_pending') {
          return DeviceCodePollResult.pending();
        }
        if (error == 'slow_down') {
          return DeviceCodePollResult.pending(slowDown: true);
        }
        if (error == 'expired_token') {
          return DeviceCodePollResult.expired();
        }
        return DeviceCodePollResult.error(
          data['error_description'] as String? ?? error,
        );
      }

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final oauthToken = OAuthTokenResponse.fromJson(data);
        if (oauthToken.accessToken.isEmpty) {
          return DeviceCodePollResult.error('Missing access_token');
        }

        final token = oauthToken.toAuthToken();
        await _persistSession(
          AuthSession(serverAddress: session.serverAddress, token: token),
        );
        return DeviceCodePollResult.complete(token);
      }

      return DeviceCodePollResult.error(
        'Unexpected status ${response.statusCode}',
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// One-step OAuth login: loopback local HTML callback + browser authorization
  Future<AuthToken> loginWithOAuth({
    required String serverAddress,
    required Future<void> Function(String authorizationUrl) openAuthorizationUrl,
    OAuthConfig config = const OAuthConfig(),
    OAuthRedirectHandler? redirectHandler,
    Duration callbackTimeout = const Duration(minutes: 5),
  }) async {
    final transport = config.resolvedRedirectTransport;
    final session = beginOAuthLogin(
      serverAddress: serverAddress,
      config: config,
    );

    _oauthLoginCancelled = false;

    if (transport == OAuthRedirectTransport.customScheme) {
      final handler = redirectHandler;
      if (handler == null) {
        throw ArgumentError(
          '当前平台使用自定义 Scheme 回调，请提供 redirectHandler',
        );
      }
      _activeOAuthRedirectHandler = handler;
      try {
        await openAuthorizationUrl(session.authorizationUrl);
        final callbackUri =
            await handler.waitForRedirect(timeout: callbackTimeout);
        if (_oauthLoginCancelled) {
          throw const OAuthLoginCancelledException();
        }
        return await completeOAuthLogin(
          session: session,
          callbackUri: callbackUri,
        );
      } catch (e) {
        if (_oauthLoginCancelled || e is OAuthLoginCancelledException) {
          throw const OAuthLoginCancelledException();
        }
        if (e is StateError &&
            e.message == 'OAuth redirect wait cancelled') {
          throw const OAuthLoginCancelledException();
        }
        if (e is TimeoutException) {
          throw Exception(
            '等待 OAuth 回调超时：浏览器未回跳到 ${config.redirectUri}。\n'
            '请确认认证中心已为 agentos-desktop 登记该 redirect_uri。',
          );
        }
        rethrow;
      } finally {
        if (_activeOAuthRedirectHandler == handler) {
          _activeOAuthRedirectHandler = null;
        }
        _oauthLoginCancelled = false;
      }
    }

    final loopback = LoopbackRedirectServer(
      host: config.redirectHost,
      port: config.redirectPort,
      callbackPath: config.redirectPath,
      loginSuccessPath: OAuthDefaults.loginSuccessPath,
      logoutSuccessPath: OAuthDefaults.logoutSuccessPath,
    );

    _activeOAuthLoginLoopback = loopback;
    var loginSucceeded = false;
    try {
      await loopback.start();
      await openAuthorizationUrl(session.authorizationUrl);
      final callbackUri =
          await loopback.waitForCallback(timeout: callbackTimeout);
      final token =
          await completeOAuthLogin(session: session, callbackUri: callbackUri);
      loginSucceeded = true;
      return token;
    } catch (e) {
      if (_oauthLoginCancelled) {
        throw const OAuthLoginCancelledException();
      }
      await loopback.stop();
      if (e is TimeoutException) {
        throw Exception(
          '等待 OAuth 回调超时：浏览器可能已在认证中心网站登录成功，但未跳转到 '
          '${config.redirectUri}。\n'
          '请检查认证中心登录页是否在成功后跳回 redirect 参数中的 /oauth2/authorize。',
        );
      }
      rethrow;
    } finally {
      if (_activeOAuthLoginLoopback == loopback) {
        _activeOAuthLoginLoopback = null;
      }
      _oauthLoginCancelled = false;
      if (loginSucceeded) {
        loopback.scheduleStop();
      }
    }
  }

  /// Refresh the access_token using the refresh_token
  Future<AuthToken> refreshToken({
    OAuthConfig config = const OAuthConfig(),
  }) async {
    final token = _currentToken;
    final serverAddress = _currentServerAddress;
    if (token == null || serverAddress == null) {
      throw Exception('未登录，无法刷新 Token');
    }

    final refreshToken = token.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw Exception('缺少 refresh_token，请重新登录');
    }

    try {
      final dio = _createDio(BaseOptions(
        baseUrl: serverApiBase(serverAddress),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          Headers.contentTypeHeader: Headers.formUrlEncodedContentType,
        },
      ));

      final response = await dio.post(
        config.tokenPath,
        data: {
          'grant_type': 'refresh_token',
          'client_id': config.clientId,
          'refresh_token': refreshToken,
        },
      );

      final oauthToken = OAuthTokenResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      if (oauthToken.accessToken.isEmpty) {
        throw Exception('刷新 Token 失败：响应缺少 access_token');
      }

      final refreshed = oauthToken.toAuthToken().copyWith(
            refreshToken: oauthToken.refreshToken ?? refreshToken,
          );

      await _persistSession(
        AuthSession(serverAddress: serverAddress, token: refreshed),
      );
      return refreshed;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Log out: ask the server to revoke the token and clear the local session
  ///
  /// `GET /api/v1/auth/logout`; sending `Authorization: Bearer <access_token>` is recommended.
  /// The server revokes the access / refresh token; it may still return success when no token is sent or the token is invalid,
  /// but an already issued token is not guaranteed to become invalid immediately.
  Future<void> logout({OAuthConfig config = const OAuthConfig()}) async {
    final token = _currentToken;
    final serverAddress = _currentServerAddress;

    if (serverAddress != null) {
      try {
        await _requestServerLogout(
          serverAddress: serverAddress,
          accessToken: token?.accessToken,
          config: config,
        );
      } catch (e) {
        await logoutLocal();
        rethrow;
      }
    }

    await logoutLocal();
  }

  /// Local logout: only clears the local session and token storage
  Future<void> logoutLocal() async {
    _currentToken = null;
    _currentServerAddress = null;
    _apiClient.clearAuthToken();
    await _tokenStorage?.clearSession();
  }

  /// Request a server-side logout
  Future<void> _requestServerLogout({
    required String serverAddress,
    String? accessToken,
    OAuthConfig config = const OAuthConfig(),
  }) async {
    final headers = <String, dynamic>{};
    if (accessToken != null && accessToken.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $accessToken';
    }

    try {
      final dio = _createDio(BaseOptions(
        baseUrl: serverApiBase(serverAddress),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: headers,
      ));

      final response = await dio.get(config.logoutPath);
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return;
      }

      final code = data['code'];
      if (code == null || code == 200 || code == 0) {
        return;
      }

      final message = data['msg'] as String? ??
          data['message'] as String? ??
          '登出失败';
      throw Exception(message);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<AuthToken> _exchangeAuthorizationCode({
    required String serverAddress,
    required OAuthConfig config,
    required String code,
    required Uri redirectUri,
    required String codeVerifier,
  }) async {
    try {
      final dio = _createDio(BaseOptions(
        baseUrl: serverApiBase(serverAddress),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          Headers.contentTypeHeader: Headers.formUrlEncodedContentType,
        },
      ));

      final response = await dio.post(
        config.tokenPath,
        data: {
          'grant_type': 'authorization_code',
          'client_id': config.clientId,
          'code': code,
          'redirect_uri': redirectUri.toString(),
          'code_verifier': codeVerifier,
        },
      );

      final oauthToken = OAuthTokenResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      if (oauthToken.accessToken.isEmpty) {
        throw Exception('换取 Token 失败：响应缺少 access_token');
      }

      return oauthToken.toAuthToken();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Dio _createDio(BaseOptions options) {
    final dio = Dio(options);
    final callback = _badCertificateCallback;
    if (callback == null) return dio;
    dio.options.followRedirects = false;

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = callback;
        return client;
      },
    );
    return dio;
  }

  void _applySession(AuthSession session) {
    _currentToken = session.token;
    _currentServerAddress = session.serverAddress;
    _apiClient.setAuthToken(session.token.accessToken);
    _apiClient.dio.options.baseUrl = serverApiBase(session.serverAddress);
  }

  Future<void> _persistSession(AuthSession session) async {
    _applySession(session);
    await _tokenStorage?.saveSession(session);
  }

  Exception _handleError(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final data = e.response!.data;

      String message = '请求失败';
      if (data is Map<String, dynamic>) {
        message = data['error_description'] as String? ??
            data['message'] as String? ??
            data['msg'] as String? ??
            data['error'] as String? ??
            message;
      } else if (data is String) {
        message = data;
      }

      switch (statusCode) {
        case 401:
          return Exception('未授权：$message');
        case 403:
          return Exception('禁止访问：$message');
        case 404:
          return Exception('资源不存在：$message');
        case 422:
          return Exception('请求参数错误：$message');
        case 500:
          return Exception('服务器错误：$message');
        default:
          return Exception('请求失败 ($statusCode)：$message');
      }
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return Exception('连接超时，请检查网络连接');
      case DioExceptionType.receiveTimeout:
        return Exception('接收超时，请检查网络连接');
      case DioExceptionType.sendTimeout:
        return Exception('发送超时，请检查网络连接');
      case DioExceptionType.connectionError:
        final errorMsg = e.message ?? '无法连接到服务器';
        final requestUri = e.requestOptions.uri.toString();
        return Exception('连接错误：$errorMsg\n请求地址: $requestUri');
      case DioExceptionType.badResponse:
        return Exception('服务器响应错误');
      case DioExceptionType.cancel:
        return Exception('请求已取消');
      case DioExceptionType.unknown:
      default:
        final errorMsg = e.message ?? '未知错误';
        return Exception('网络错误：$errorMsg (类型: ${e.type})');
    }
  }
}

/// The user cancelled the OAuth login (e.g. closed the login dialog)
class OAuthLoginCancelledException implements Exception {
  const OAuthLoginCancelledException();

  @override
  String toString() => 'OAuth 登录已取消';
}
