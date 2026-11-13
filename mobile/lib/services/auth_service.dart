import 'package:dio/dio.dart';

import '../core/config.dart';

class AuthApiService {
  AuthApiService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
          headers: {'Content-Type': 'application/json'},
        ),
      );

  final Dio _dio;

  Future<Map<String, dynamic>> register({
    required String userId,
    required String password,
    String? publicKey,
  }) async {
    final response = await _dio.post(
      '/api/auth/register',
      data: {
        'userId': userId,
        'password': password,
        if (publicKey != null && publicKey.isNotEmpty) 'publicKey': publicKey,
      },
    );
    return _decodeBody(response);
  }

  Future<void> setPin({
    required String accessToken,
    required String pin,
  }) async {
    await _dio.post(
      '/api/auth/pin',
      data: {'pin': pin},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  Future<Map<String, dynamic>> login({
    required String userId,
    required String password,
  }) async {
    final response = await _dio.post(
      '/api/auth/login',
      data: {'userId': userId, 'password': password},
    );
    return _decodeBody(response);
  }

  Future<void> logout({required String refreshToken}) async {
    await _dio.post('/api/auth/logout', data: {'refreshToken': refreshToken});
  }

  Future<Map<String, dynamic>> getMe({required String accessToken}) async {
    final response = await _dio.get(
      '/api/users/me',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return _decodeBody(response);
  }

  Future<void> updatePublicKey({
    required String accessToken,
    required String publicKey,
  }) async {
    await _dio.put(
      '/api/users/me/public-key',
      data: {'publicKey': publicKey},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  Map<String, dynamic> _decodeBody(Response response) {
    if (response.data is Map<String, dynamic>) {
      return response.data as Map<String, dynamic>;
    }
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw const FormatException('Unexpected auth API response format');
  }
}
