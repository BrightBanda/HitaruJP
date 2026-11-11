import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/shared/widgets/app_logo.dart';
import 'package:ingrain/shared/widgets/double_back_to_exit.dart';

/// Holds an email/password learner until they open the link in the
/// verification email.
///
/// Verifying happens in a browser, so the app cannot be told about it; it asks
/// Firebase every few seconds and whenever the app comes back to the
/// foreground, which is usually right after the learner tapped the link.
class VerifyEmailView extends ConsumerStatefulWidget {
  const VerifyEmailView({super.key});

  static const pollInterval = Duration(seconds: 5);
  static const resendCooldown = Duration(seconds: 60);

  @override
  ConsumerState<VerifyEmailView> createState() => _VerifyEmailViewState();
}

class _VerifyEmailViewState extends ConsumerState<VerifyEmailView>
    with WidgetsBindingObserver {
  Timer? _poll;
  Timer? _cooldownTicker;
  int _cooldownLeft = 0;
  bool _checking = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(VerifyEmailView.pollInterval, (_) => _check());
    // The first email went out with the sign-up, so start on a cooldown
    // rather than inviting an immediate duplicate.
    _startCooldown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _cooldownTicker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<bool> _check() =>
      ref.read(authViewModelProvider.notifier).checkEmailVerified();

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    final verified = await _check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (!verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Not verified yet. Open the link in the email, then try again.',
          ),
        ),
      );
    }
  }

  Future<void> _resend() async {
    if (_resending || _cooldownLeft > 0) return;
    setState(() => _resending = true);
    final error = await ref
        .read(authViewModelProvider.notifier)
        .resendVerificationEmail();
    if (!mounted) return;
    setState(() => _resending = false);
    if (error == null) _startCooldown();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Sent. Check your inbox and spam.')),
    );
  }

  void _startCooldown() {
    _cooldownTicker?.cancel();
    setState(() => _cooldownLeft = VerifyEmailView.resendCooldown.inSeconds);
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldownLeft--);
      if (_cooldownLeft <= 0) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authVm = ref.read(authViewModelProvider.notifier);
    final email = authVm.email;

    return DoubleBackToExit(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Verify your email'),
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
                  Icon(
                    Icons.mark_email_unread_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Check your inbox',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    email == null
                        ? 'We sent you a verification link.'
                        : 'We sent a verification link to $email. Open it, '
                              'then come back here.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Can't find it? Check your spam folder.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _checking ? null : _checkNow,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _checking
                        ? const _ButtonSpinner()
                        : const Text("I've verified my email"),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _resending || _cooldownLeft > 0 ? null : _resend,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _resending
                        ? const _ButtonSpinner()
                        : Text(
                            _cooldownLeft > 0
                                ? 'Resend email ($_cooldownLeft s)'
                                : 'Resend email',
                          ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: authVm.signOut,
                    child: const Text('Use a different account'),
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

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(strokeWidth: 2.5),
  );
}
