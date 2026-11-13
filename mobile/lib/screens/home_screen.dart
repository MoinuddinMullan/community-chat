import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import 'chats/chat_list_screen.dart';
import 'contacts/user_search_screen.dart';
import 'contacts/contact_list_screen.dart';
import 'requests/request_list_screen.dart';
import 'settings/settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _HomeTabPage(title: 'Chats', icon: Icons.chat_bubble_outline_rounded),
      _HomeTabPage(title: 'Requests', icon: Icons.person_add_alt_1_rounded),
      _HomeTabPage(title: 'Contacts', icon: Icons.contacts_rounded),
      _HomeTabPage(title: 'Settings', icon: Icons.settings_rounded),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.appName),
          actions: [
            IconButton(
              tooltip: 'Find a neighbour',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UserSearchScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => context.read<AuthProvider>().logout(),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: CommunityTheme.green,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: tabs
                .map((tab) => Tab(icon: Icon(tab.icon), text: tab.title))
                .toList(),
          ),
        ),
        body: const TabBarView(
          children: [
            ChatListScreen(),
            RequestListScreen(),
            ContactListScreen(),
            SettingsScreen(),
          ],
        ),
      ),
    );
  }
}

class _HomeTabPage {
  const _HomeTabPage({required this.title, required this.icon});

  final String title;
  final IconData icon;
}
