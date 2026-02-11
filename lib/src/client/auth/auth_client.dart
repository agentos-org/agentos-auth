import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

import '../../models/token.dart';
import '../../utils/api_client.dart';
import '../../utils/token_storage.dart';
import 'dto.dart';

const String _gatewayPrefix = '/liteAgent';

String _getDefaultTokenStoragePath() {
  final homeDir = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Platform.environment['APPDATA'] ??
      '';
  return path.join(homeDir, '.agentos', 'auth', 'token.json');
}

String _buildBaseUrl(String serverAddress) {
  if (serverAddress.isEmpty) return _gatewayPrefix;
  if (serverAddress.endsWith('/')) {
    return serverAddress.substring(0, serverAddress.length - 1) + _gatewayPrefix;
  }
  return '$serverAddress$_gatewayPrefix';
}

/// 认证客户端
///
/// 提供登录、登出、Token 管理等功能。
/// 默认使用 DefaultTokenStorage 持久化 Token。
class AuthClient {
  AuthClient({
    ApiClient? apiClient,
    String? baseUrl,
    TokenStorage? tokenStorage,
    String? storagePath,
  })  : _apiClient = apiClient ?? ApiClient(baseUrl: baseUrl),
        _tokenStorage = tokenStorage ?? 
            (storagePath != null 
                ? DefaultTokenStorage(storagePath: storagePath)
                : DefaultTokenStorage(storagePath: _getDefaultTokenStoragePath()));

  final ApiClient _apiClient;
  final TokenStorage? _tokenStorage;

  AuthToken? _currentToken;
  String? _currentServerAddress;

  /// 当前 Token
  AuthToken? get currentToken => _currentToken;

  /// 当前服务器地址
  String? get currentServerAddress => _currentServerAddress;

  /// 是否已认证
  bool get isAuthenticated => _currentToken != null;

  /// 从存储加载 Token
  Future<void> initialize({String? serverAddress}) async {
    if (_tokenStorage == null) return;

    final token = await _tokenStorage.loadToken();
    if (token != null) {
      _currentToken = token;
      _apiClient.setAuthToken(token.accessToken);
      
      if (serverAddress != null) {
        _currentServerAddress = serverAddress;
        _apiClient.dio.options.baseUrl = _buildBaseUrl(serverAddress);
      }
    }
  }

  /// 登录
  /// 
  /// [serverAddress] 服务器地址，例如 "https://api.example.com"
  /// [email] 邮箱（登录凭证）
  /// [password] 密码
  Future<LoginResponse> login({
    required String serverAddress,
    required String email,
    required String password,
  }) async {
    try {
      final apiClient = ApiClient(baseUrl: _buildBaseUrl(serverAddress));
      final response = await apiClient.dio.post(
        '/v1/agentOS/login',
        queryParameters: {
          'email': email,
          'password': password,
        },
      );

      final loginResponse = LoginResponse.fromJson(
        response.data as Map<String, dynamic>,
      );

      if (loginResponse.code != 0 && loginResponse.code != 200) {
        throw Exception('登录失败: ${loginResponse.message}');
      }

      _currentToken = loginResponse.token;
      _currentServerAddress = serverAddress;
      _apiClient.setAuthToken(loginResponse.token.accessToken);
      _apiClient.dio.options.baseUrl = _buildBaseUrl(serverAddress);

      await _tokenStorage?.saveToken(loginResponse.token);

      return loginResponse;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 刷新 Token
  Future<LoginResponse> refreshToken() async {
    if (_currentToken == null || _currentServerAddress == null) {
      throw Exception('未登录，无法刷新 Token');
    }

    try {
      final apiClient = ApiClient(baseUrl: _buildBaseUrl(_currentServerAddress!));
      apiClient.setAuthToken(_currentToken!.accessToken);
      
      final response = await apiClient.dio.post('/v1/agentOS/refreshToken');
      
      final refreshResponse = LoginResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      
      if (refreshResponse.code != 0 && refreshResponse.code != 200) {
        throw Exception('刷新 Token 失败: ${refreshResponse.message}');
      }

      _currentToken = refreshResponse.token;
      _apiClient.setAuthToken(refreshResponse.token.accessToken);
      await _tokenStorage?.saveToken(refreshResponse.token);

      return refreshResponse;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 登出
  Future<void> logout() async {
    try {
      if (_currentToken != null && _currentServerAddress != null) {
        final apiClient = ApiClient(baseUrl: _buildBaseUrl(_currentServerAddress!));
        apiClient.setAuthToken(_currentToken!.accessToken);
        
        final response = await apiClient.dio.post('/v1/agentOS/logout');
        
        final logoutResponse = LogoutResponse.fromJson(
          response.data as Map<String, dynamic>,
        );
        
        if (logoutResponse.code != 0 && logoutResponse.code != 200) {
          throw Exception('登出失败: ${logoutResponse.message}');
        }
      }
    } on DioException catch (e) {
      throw _handleError(e);
    } finally {
      _currentToken = null;
      _currentServerAddress = null;
      _apiClient.clearAuthToken();
      await _tokenStorage?.clearToken();
    }
  }

  Exception _handleError(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final data = e.response!.data;

      String message = '请求失败';
      if (data is Map<String, dynamic> && data.containsKey('message')) {
        message = data['message'] as String;
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
