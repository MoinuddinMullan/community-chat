import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/chat_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _controller = TextEditingController();
  UserSearchResult? _result;
  String? _error;
  bool _isSearching = false;
  bool _isSendingRequest = false;
  bool _requestSent = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final userId = _controller.text.trim();
    if (userId.isEmpty || _isSearching) return;

    setState(() {
      _isSearching = true;
      _error = null;
      _result = null;
      _requestSent = false;
    });

    try {
      final result = await context.read<CommunityProvider>().searchUser(userId);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _sendRequest() async {
    final result = _result;
    if (result == null || _isSendingRequest) return;

    setState(() {
      _isSendingRequest = true;
      _error = null;
    });
    try {
      await context.read<CommunityProvider>().sendConnectionRequest(
        result.userId,
      );
      if (mounted) setState(() => _requestSent = true);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _isSendingRequest = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final body = error.response?.data;
      if (body is Map &&
          body['error'] is Map &&
          body['error']['message'] is String) {
        return body['error']['message'] as String;
      }
      if (error.response == null) {
        return 'Could not reach the server. Check your connection and try again.';
      }
    }
    if (error is StateError) return error.message;
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthProvider>().userId?.toLowerCase();
    final isSelf = _result?.userId.toLowerCase() == currentUserId;

    return Scaffold(
      appBar: AppBar(title: const Text('Find a neighbour')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Search by exact user ID',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Find someone in your community, then send a connection request to start a chat.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'User ID',
              hintText: 'Enter their user ID',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _isSearching ? null : _search,
                icon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isSearching ? null : _search,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Search'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_result case final result?) ...[
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  child: Text(
                    result.displayName.characters.first.toUpperCase(),
                  ),
                ),
                title: Text(
                  result.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('@${result.userId}'),
                trailing: isSelf
                    ? const Text('You')
                    : _requestSent
                    ? const Icon(Icons.check_circle, color: AppColors.brand)
                    : null,
              ),
            ),
            if (!isSelf) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isSendingRequest || _requestSent
                    ? null
                    : _sendRequest,
                icon: _isSendingRequest
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _requestSent
                            ? Icons.check_rounded
                            : Icons.person_add_alt_1_rounded,
                      ),
                label: Text(
                  _requestSent ? 'Request sent' : 'Send connection request',
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
