import 'package:dio/dio.dart';

/// Base HTTP client
class ApiClient {
  ApiClient({
    Dio? dio,
    BaseOptions? baseOptions,
    String? baseUrl,
  }) : _dio = dio ??
            Dio(
              baseOptions ??
                  BaseOptions(
                    baseUrl: baseUrl ?? 'http://localhost:8080/api',
                    connectTimeout: const Duration(seconds: 10),
                    receiveTimeout: const Duration(seconds: 30),
                    headers: <String, dynamic>{
                      'Content-Type': 'application/json',
                      'Accept': 'application/json',
                    },
                  ),
            );

  final Dio _dio;

  Dio get dio => _dio;

  /// Set the authentication token
  void setAuthToken(String? token) {
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  /// Clear the authentication token
  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }
}
