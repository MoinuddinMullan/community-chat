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
      _HomeTabPage(
        title: 'Chats',
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_rounded,
      ),
      _HomeTabPage(
        title: 'Requests',
        icon: Icons.person_add_alt_1_outlined,
        selectedIcon: Icons.person_add_alt_1_rounded,
      ),
      _HomeTabPage(
        title: 'Contacts',
        icon: Icons.contacts_outlined,
        selectedIcon: Icons.contacts_rounded,
      ),
      _HomeTabPage(
        title: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          void openUserSearch() {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const UserSearchScreen()));
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text(AppStrings.appName),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  onPressed: () => context.read<AuthProvider>().logout(),
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: SizedBox(
                    height: 48,
                    child: Tooltip(
                      message: 'Find a neighbour',
                      child: Material(
                        color: AppColors.searchFill,
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: openUserSearch,
                          child: Row(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 16),
                                child: Icon(
                                  Icons.search_rounded,
                                  color: AppColors.textPrimary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'Search',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      ChatListScreen(),
                      RequestListScreen(),
                      ContactListScreen(),
                      SettingsScreen(),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: AnimatedBuilder(
              animation: tabController,
              builder: (context, _) => NavigationBar(
                selectedIndex: tabController.index,
                onDestinationSelected: tabController.animateTo,
                destinations: tabs
                    .map(
                      (tab) => NavigationDestination(
                        icon: Icon(tab.icon, size: 24),
                        selectedIcon: Icon(tab.selectedIcon, size: 24),
                        label: tab.title,
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeTabPage {
  const _HomeTabPage({
    required this.title,
    required this.icon,
    required this.selectedIcon,
  });

  final String title;
  final IconData icon;
  final IconData selectedIcon;
}
