import 'package:flutter/foundation.dart';

class AppConfig {
  static const appName = 'Community Chat';
  static const packageId = 'com.community.community_chat';

  static String get apiBaseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    if (kIsWeb) {
      return 'http://localhost:4000';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:4000'
        : 'http://localhost:4000';
  }
}
