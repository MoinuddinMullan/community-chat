import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Set your four-digit PIN')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const Text(
                  'Create a four-digit PIN to use every time you open the app.',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),
                _pinField(
                  controller: _pinController,
                  label: 'New four-digit PIN',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                _pinField(
                  controller: _confirmController,
                  label: 'Confirm PIN',
                  validator: (value) {
                    if (value == null || !RegExp(r'^\d{4}$').hasMatch(value)) {
                      return 'Enter exactly four digits';
                    }
                    if (value != _pinController.text) {
                      return 'PINs do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: provider.isLoading ? null : _savePin,
                  style: FilledButton.styleFrom(
                    backgroundColor: CommunityTheme.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                  ),
                  child: provider.isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save PIN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pinField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputAction textInputAction = TextInputAction.done,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(labelText: label),
      validator:
          validator ??
          (value) => value == null || !RegExp(r'^\d{4}$').hasMatch(value)
              ? 'Enter exactly four digits'
              : null,
    );
  }

  Future<void> _savePin() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await context.read<AuthProvider>().setPin(
      _pinController.text,
    );
    if (!mounted || success) return;

    final error = context.read<AuthProvider>().errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Could not save your PIN. Try again.')),
    );
  }
}
