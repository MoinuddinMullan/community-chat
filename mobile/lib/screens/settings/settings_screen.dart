import 'package:flutter/material.dart';

import '../../core/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Privacy & Security',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 12),
                Text('Messages are encrypted on-device and disappear after 7 days.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const ListTile(
          leading: Icon(Icons.key_rounded, color: CommunityTheme.teal),
          title: Text('Encryption keys'),
          subtitle: Text('Review the local key status'),
        ),
        const ListTile(
          leading: Icon(Icons.notifications_rounded, color: CommunityTheme.teal),
          title: Text('Notifications'),
          subtitle: Text('Private updates and new requests'),
        ),
        const ListTile(
          leading: Icon(Icons.download_rounded, color: CommunityTheme.teal),
          title: Text('Data export'),
          subtitle: Text('Download your community archive'),
        ),
      ],
    );
  }
}
