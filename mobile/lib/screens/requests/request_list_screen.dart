import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../providers/community_provider.dart';

class RequestListScreen extends StatefulWidget {
  const RequestListScreen({super.key});

  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommunityProvider>().loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CommunityProvider>(
      builder: (context, provider, _) {
        final requests = provider.requests;

        if (provider.isLoading && requests.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (requests.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No pending connection requests.'),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: provider.refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final request = requests[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: CommunityTheme.teal,
                        child: Text(
                          request.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                            ),
                            const SizedBox(height: 6),
                            Text(request.message, style: TextStyle(color: Colors.grey.shade700)),
                            const SizedBox(height: 12),
                            if (request.isIncoming)
                              Row(
                                children: [
                                  FilledButton.tonal(
                                    onPressed: () => provider.acceptRequest(request.id),
                                    child: const Text('Accept'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () => provider.declineRequest(request.id),
                                    child: const Text('Ignore'),
                                  ),
                                ],
                              )
                            else
                              TextButton(
                                onPressed: () => provider.declineRequest(request.id),
                                child: const Text('Cancel request'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
