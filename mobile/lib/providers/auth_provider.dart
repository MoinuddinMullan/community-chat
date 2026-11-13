import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/crypto_service.dart';
import '../services/secure_store.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider() : _authApi = AuthApiService();

  final AuthApiService _authApi;
  final SecureStore _secureStore = SecureStore();
  final CryptoService _cryptoService = CryptoService();

  bool isAuthenticated = false;
  bool isInitialized = false;
  bool isLoading = false;
  bool requiresPinSetup = false;
  String? errorMessage;
  String? userId;
  String? rememberedUserId;
  String? userSubjectId;
  String? displayName;
  String? accessToken;
  String? refreshToken;
  String? publicKey;
  String? privateKey;
  Future<void>? _identityFuture;

  Future<void> initialize() async {
    try {
      var savedUserId = await _secureStore.read('remembered_user_id');
      final legacySession = await _secureStore.read('auth_session');
      if ((savedUserId == null || savedUserId.trim().isEmpty) &&
          legacySession != null &&
          legacySession.isNotEmpty) {
        try {
          final decoded = Map<String, dynamic>.from(jsonDecode(legacySession));
          savedUserId = decoded['userId'] as String?;
          if (savedUserId != null && savedUserId.trim().isNotEmpty) {
            await _secureStore.write('remembered_user_id', savedUserId);
          }
        } on FormatException {
          errorMessage = 'Your saved sign-in needs to be set up again.';
        } on TypeError {
          errorMessage = 'Your saved sign-in needs to be set up again.';
        }
      }
      await _secureStore.delete('auth_session');
      rememberedUserId = savedUserId?.trim().isEmpty == true
          ? null
          : savedUserId?.trim();
    } catch (error) {
      errorMessage = 'Could not read the saved account on this device. Please sign in again.';
      debugPrint('Failed to initialize the saved account: $error');
    } finally {
      isInitialized = true;
      notifyListeners();
    }
  }

  Future<bool> unlockWithPin(String pin) async {
    final savedUserId = rememberedUserId;
    if (savedUserId == null || savedUserId.isEmpty) {
      errorMessage = 'No saved account was found. Please sign in again.';
      notifyListeners();
      return false;
    }
    return login(userIdInput: savedUserId, password: pin);
  }

  Future<bool> login({
    required String userIdInput,
    required String password,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final payload = await _authApi.login(
        userId: userIdInput,
        password: password,
      );
      final me = payload['me'] as Map<String, dynamic>?;
      final newAccessToken = payload['accessToken'] as String?;
      final newRefreshToken = payload['refreshToken'] as String?;
      requiresPinSetup = payload['requiresPinSetup'] == true;

      if (me == null || newAccessToken == null || newRefreshToken == null) {
        errorMessage = 'The server returned an incomplete sign-in response. Please try again.';
        return false;
      }

      final uid = me['userId'] as String? ?? userIdInput;
      final identity = await _getOrCreateIdentity(
        userId: uid,
        serverPublicKey: me['publicKey'] as String?,
        accessToken: newAccessToken,
      );
      await setSession(
        uid: uid,
        name: me['displayName'] as String? ?? userIdInput,
        accessTokenValue: newAccessToken,
        refreshTokenValue: newRefreshToken,
        publicKeyValue: identity['publicKey']!,
        privateKeyValue: identity['privateKey']!,
      );
      return true;
    } catch (error) {
      errorMessage = _getErrorMessage(error);
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String userIdInput,
    required String password,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final keyPair = await _cryptoService.generateKeyPair();
      final publicKeyValue = await _cryptoService.publicKeyToBase64(keyPair);
      final privateKeyValue = await _cryptoService.privateKeyToBase64(keyPair);
      final payload = await _authApi.register(
        userId: userIdInput,
        password: password,
        publicKey: publicKeyValue,
      );
      final me = payload['me'] as Map<String, dynamic>?;
      final newAccessToken = payload['accessToken'] as String?;
      final newRefreshToken = payload['refreshToken'] as String?;

      if (me == null || newAccessToken == null || newRefreshToken == null) {
        errorMessage = 'The server returned an incomplete registration response. Please try again.';
        return false;
      }

      final uid = me['userId'] as String? ?? userIdInput;
      if (publicKeyValue != me['publicKey']) {
        await _authApi.updatePublicKey(
          accessToken: newAccessToken,
          publicKey: publicKeyValue,
        );
      }
      await setSession(
        uid: uid,
        name: me['displayName'] as String? ?? uid,
        accessTokenValue: newAccessToken,
        refreshTokenValue: newRefreshToken,
        publicKeyValue: publicKeyValue,
        privateKeyValue: privateKeyValue,
      );
      requiresPinSetup = false;
      return true;
    } catch (error) {
      errorMessage = _getErrorMessage(error);
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  String _getErrorMessage(Object error) {
    if (error is DioException) {
      final response = error.response?.data;
      final statusCode = error.response?.statusCode;
      if (response is Map) {
        final details = response['error'];
        if (statusCode != null && statusCode >= 500) {
          return 'The server is temporarily unavailable. Please try again in a moment.';
        }
        if (details is Map && details['message'] is String) {
          return details['message'] as String;
        }
      }

      if (error.response == null) {
        return 'Could not reach the server. Check that the backend is running and try again.';
      }
    }

    return 'Something went wrong. Please try again.';
  }

  String? _subjectFromAccessToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is Map && payload['sub'] is String) {
        final subject = (payload['sub'] as String).trim();
        return subject.isEmpty ? null : subject;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> setSession({
    required String uid,
    required String name,
    required String accessTokenValue,
    required String refreshTokenValue,
    required String publicKeyValue,
    required String privateKeyValue,
  }) async {
    userId = uid;
    rememberedUserId = uid;
    userSubjectId = _subjectFromAccessToken(accessTokenValue);
    displayName = name;
    accessToken = accessTokenValue;
    refreshToken = refreshTokenValue;
    publicKey = publicKeyValue;
    privateKey = privateKeyValue;
    isAuthenticated = true;

    await _storeIdentity(uid, publicKeyValue, privateKeyValue);
    await _secureStore.write('remembered_user_id', uid);
    await _secureStore.delete('auth_session');

    notifyListeners();
  }

  Future<bool> setPin(String pin) async {
    final token = accessToken;
    if (token == null || !requiresPinSetup) {
      errorMessage = 'Sign in to an existing account before setting its PIN.';
      notifyListeners();
      return false;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _authApi.setPin(accessToken: token, pin: pin);
      requiresPinSetup = false;
      return true;
    } catch (error) {
      errorMessage = _getErrorMessage(error);
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> forgetRememberedAccount() async {
    if (isAuthenticated) return;
    await _secureStore.delete('remembered_user_id');
    rememberedUserId = null;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> ensureEncryptionIdentity() {
    if (publicKey != null && privateKey != null) return Future.value();
    return _identityFuture ??= _createMissingIdentity();
  }

  Future<void> _createMissingIdentity() async {
    final uid = userId;
    final token = accessToken;
    if (uid == null || token == null) {
      throw StateError('Sign in before setting up chat encryption.');
    }

    try {
      final me = await _authApi.getMe(accessToken: token);
      final identity = await _getOrCreateIdentity(
        userId: uid,
        serverPublicKey: me['publicKey'] as String?,
        accessToken: token,
      );
      publicKey = identity['publicKey'];
      privateKey = identity['privateKey'];
      notifyListeners();
    } finally {
      _identityFuture = null;
    }
  }

  Future<Map<String, String>> _getOrCreateIdentity({
    required String userId,
    required String? serverPublicKey,
    required String accessToken,
  }) async {
    final keyId = userId.toLowerCase();
    final savedPublicKey = await _secureStore.read('identity_public_$keyId');
    final savedPrivateKey = await _secureStore.read('identity_private_$keyId');
    if (savedPublicKey != null && savedPrivateKey != null) {
      if (savedPublicKey == serverPublicKey) {
        return {'publicKey': savedPublicKey, 'privateKey': savedPrivateKey};
      }
      if (serverPublicKey == null) {
        await _authApi.updatePublicKey(
          accessToken: accessToken,
          publicKey: savedPublicKey,
        );
        return {'publicKey': savedPublicKey, 'privateKey': savedPrivateKey};
      }
    }

    final pair = await _cryptoService.generateKeyPair();
    final publicKeyValue = await _cryptoService.publicKeyToBase64(pair);
    final privateKeyValue = await _cryptoService.privateKeyToBase64(pair);
    await _authApi.updatePublicKey(
      accessToken: accessToken,
      publicKey: publicKeyValue,
    );
    await _storeIdentity(userId, publicKeyValue, privateKeyValue);
    return {'publicKey': publicKeyValue, 'privateKey': privateKeyValue};
  }

  Future<void> _storeIdentity(
    String userId,
    String publicKeyValue,
    String privateKeyValue,
  ) async {
    final keyId = userId.toLowerCase();
    await _secureStore.write('identity_public_$keyId', publicKeyValue);
    await _secureStore.write('identity_private_$keyId', privateKeyValue);
  }

  Future<void> logout() async {
    if (refreshToken != null && refreshToken!.isNotEmpty) {
      try {
        await _authApi.logout(refreshToken: refreshToken!);
      } catch (_) {
        // Ignore server-side logout errors and clear the local session anyway.
      }
    }

    userId = null;
    userSubjectId = null;
    displayName = null;
    accessToken = null;
    refreshToken = null;
    publicKey = null;
    privateKey = null;
    isAuthenticated = false;
    requiresPinSetup = false;
    rememberedUserId = null;
    await _secureStore.delete('auth_session');
    await _secureStore.delete('remembered_user_id');
    notifyListeners();
  }
}
