import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

enum AuthMode { login, register, pinUnlock }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.mode, this.initialUserId});

  final AuthMode mode;
  final String? initialUserId;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _useLegacyPassword = false;

  @override
  void initState() {
    super.initState();
    _userIdController.text = widget.initialUserId ?? '';
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = widget.mode == AuthMode.register;
    final isPinUnlock = widget.mode == AuthMode.pinUnlock;
    final isLoading = context.watch<AuthProvider>().isLoading;
    final authProvider = context.watch<AuthProvider>();
    final isPinEntry = isRegister || isPinUnlock || !_useLegacyPassword;
    final title = isRegister
        ? 'Create account'
        : isPinUnlock
        ? 'Enter your PIN'
        : 'Log in';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                if (isPinUnlock) ...[
                  Text(
                    'Welcome back, @${authProvider.rememberedUserId ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  TextFormField(
                    controller: _userIdController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'User name'),
                    validator: (value) {
                      final userId = value?.trim() ?? '';
                      if (!RegExp(
                        r'^[a-z0-9_.]{3,20}$',
                        caseSensitive: false,
                      ).hasMatch(userId)) {
                        return 'Use 3-20 letters, numbers, periods, or underscores';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  keyboardType: isPinEntry
                      ? TextInputType.number
                      : TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: isPinEntry
                      ? const [AutofillHints.oneTimeCode]
                      : null,
                  inputFormatters: isPinEntry
                      ? [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ]
                      : null,
                  decoration: InputDecoration(
                    labelText: isPinEntry ? '4-digit PIN' : 'Current password',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (isPinEntry) {
                      if (value == null ||
                          !RegExp(r'^\d{4}$').hasMatch(value)) {
                        return 'Enter exactly four digits';
                      }
                    } else if (value == null ||
                        value.length < 8 ||
                        value.length > 128) {
                      return 'Enter your existing password (8-128 characters)';
                    }
                    return null;
                  },
                ),
                if (widget.mode == AuthMode.login) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _useLegacyPassword = !_useLegacyPassword;
                          _passwordController.clear();
                        });
                      },
                      child: Text(
                        _useLegacyPassword
                            ? 'Use a four-digit PIN'
                            : 'Existing account? Use your old password once',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: isLoading ? null : _submit,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(
                    isRegister
                        ? 'Create account'
                        : isPinUnlock
                        ? 'Unlock'
                        : 'Log in',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: CommunityTheme.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isPinUnlock) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuthScreen(
                          mode: AuthMode.login,
                          initialUserId: authProvider.rememberedUserId,
                        ),
                      ),
                    ),
                    child: const Text('I have an existing account password'),
                  ),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => context
                              .read<AuthProvider>()
                              .forgetRememberedAccount(),
                    child: const Text('Use another account'),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  AppStrings.encryptionNotice,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final userId = _userIdController.text.trim().toLowerCase();
    final password = _passwordController.text;

    final bool ok;
    if (widget.mode == AuthMode.pinUnlock) {
      ok = await provider.unlockWithPin(password);
    } else if (widget.mode == AuthMode.register) {
      ok = await provider.register(userIdInput: userId, password: password);
    } else {
      ok = await provider.login(userIdInput: userId, password: password);
    }

    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            provider.errorMessage ??
                'Unable to sign in. Check your details and try again.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
