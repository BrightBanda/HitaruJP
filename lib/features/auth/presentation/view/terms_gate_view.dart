import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/auth/presentation/widgets/terms_agreement.dart';
import 'package:ingrain/shared/widgets/app_logo.dart';
import 'package:ingrain/shared/widgets/double_back_to_exit.dart';

/// Holds a signed-in learner who has not accepted the terms in force: a new
/// Google account, an account from before the terms existed, or anyone after
/// the terms change. Nothing else in the app opens until they agree.
class TermsGateView extends ConsumerStatefulWidget {
  const TermsGateView({super.key});

  @override
  ConsumerState<TermsGateView> createState() => _TermsGateViewState();
}

class _TermsGateViewState extends ConsumerState<TermsGateView> {
  bool _agreed = false;
  bool _tried = false;
  bool _busy = false;

  Future<void> _continue() async {
    if (!_agreed) {
      setState(() => _tried = true);
      return;
    }
    setState(() => _busy = true);
    final error = await ref.read(authViewModelProvider.notifier).acceptTerms();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DoubleBackToExit(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Before you continue'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo.tile(),
                  const SizedBox(height: 24),
                  Text(
                    'Terms and privacy',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'To use HitaruJP, please read and accept our Terms of '
                    'Service and Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  TermsAgreement(
                    value: _agreed,
                    onChanged: (value) => setState(() => _agreed = value),
                    errorText: _tried && !_agreed
                        ? 'Tick the box to continue'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _continue,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Agree and continue'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : ref.read(authViewModelProvider.notifier).signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
