import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/view/onboarding_flow_view.dart';
import 'package:ingrain/shared/widgets/app_logo.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:ingrain/shared/widgets/double_back_to_exit.dart';

/// Doubles as the sign-in screen and the entry to the onboarding questions.
///
/// The router sends anyone who is not `isOnboarded` here, so all three states have
/// to be reachable from this one view: signed out, signed in but not onboarded,
/// and the brief moment before the redirect fires.
class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final _signInFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isCreateMode = false;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      return await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitCredentials() async {
    if (!_signInFormKey.currentState!.validate()) return;
    final authVm = ref.read(authViewModelProvider.notifier);
    await _run(
      () => _isCreateMode
          ? authVm.createAccount(
              _emailController.text,
              _passwordController.text,
            )
          : authVm.signInWithEmail(
              _emailController.text,
              _passwordController.text,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authViewModelProvider);
    final theme = Theme.of(context);

    if (authState.isLoading) return const _StartupSplash();
    if (authState.isSignedIn) return const OnboardingFlowView();

    return DoubleBackToExit(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Welcome to HitaruJP'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _buildSignInStep(theme, authState.error),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignInStep(ThemeData theme, String? error) {
    final authVm = ref.read(authViewModelProvider.notifier);
    return Form(
      key: _signInFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo.tile(),
          const SizedBox(height: 24),
          Text('Sign in', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Your vocabulary, review history and immersion sessions follow your '
            'account across devices.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(
                label: 'Videos',
                icon: Icons.smart_display,
                color: AppColors.primaryMain,
              ),
              Pill(
                label: 'Dialogues',
                icon: Icons.forum,
                color: AppColors.primaryMain,
              ),
              Pill(
                label: 'Reviews',
                icon: Icons.school,
                color: AppColors.primaryMain,
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(authVm.signInWithGoogle),
            icon: const Icon(Icons.login),
            label: const Text('Continue with Google'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: theme.textTheme.bodySmall),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email),
            ),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter an email address'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            obscureText: true,
            validator: (v) {
              if (_isCreateMode && (v == null || v.length < 6)) {
                return 'Use at least 6 characters';
              }
              return (v == null || v.isEmpty) ? 'Enter a password' : null;
            },
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submitCredentials,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(_isCreateMode ? 'Create account' : 'Sign in'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _isCreateMode = !_isCreateMode),
            child: Text(
              _isCreateMode
                  ? 'Already have an account? Sign in'
                  : 'New here? Create an account',
            ),
          ),
        ],
      ),
    );
  }
}

/// What shows while the session is restored on a first launch (returning
/// learners start from their cached profile and skip it): the app's mark,
/// so it reads as the app starting rather than a page stuck loading.
class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/branding/logo_mark.png',
              width: 88,
              height: 88,
              cacheWidth: 264,
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 120,
              child: LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ),
      ),
    );
  }
}
