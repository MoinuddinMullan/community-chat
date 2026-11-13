class AppConfig {
  static const appName = 'Community Chat';
  static const packageId = 'com.community.community_chat';

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://community-chat-1oad.onrender.com',
  );
  static const connectTimeout = Duration(seconds: 30);
  static const receiveTimeout = Duration(seconds: 60);
  static const sendTimeout = Duration(seconds: 60);
}
