import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/community_provider.dart';
import 'screens/welcome_screen.dart';

class CommunityApp extends StatelessWidget {
  const CommunityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProxyProvider<AuthProvider, CommunityProvider>(
          create: (context) => CommunityProvider(
            accessToken: context.read<AuthProvider>().accessToken ?? '',
          ),
          update: (context, auth, previous) {
            previous?.updateToken(auth.accessToken);
            if (previous == null) {
              return CommunityProvider(accessToken: auth.accessToken ?? '');
            }
            return previous;
          },
        ),
      ],
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: CommunityTheme.light(),
        home: const WelcomeScreen(),
      ),
    );
  }
}
