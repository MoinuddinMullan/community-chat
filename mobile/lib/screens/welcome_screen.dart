import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import 'auth/auth_screen.dart';
import 'auth/pin_setup_screen.dart';
import 'home_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (!auth.isInitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (auth.requiresPinSetup) return const PinSetupScreen();
        if (auth.isAuthenticated) return const HomeScreen();
        if (auth.rememberedUserId != null) {
          return const AuthScreen(mode: AuthMode.pinUnlock);
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.groups_rounded,
                    size: 88,
                    color: CommunityTheme.teal,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppStrings.welcomeTitle,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: CommunityTheme.teal,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppStrings.welcomeSubtitle,
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const AuthScreen(mode: AuthMode.register),
                        ),
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text(AppStrings.createAccount),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CommunityTheme.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const AuthScreen(mode: AuthMode.login),
                        ),
                      ),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text(AppStrings.login),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CommunityTheme.teal,
                        side: const BorderSide(
                          color: CommunityTheme.teal,
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
