import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:ingrain/features/auth/domain/terms_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// "I agree to the Terms of Service and Privacy Policy", with a checkbox and
/// both documents a tap away. [errorText] shows under it when the learner
/// tried to go on without ticking it.
class TermsAgreement extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? errorText;
  final String termsUrl;
  final String privacyUrl;

  const TermsAgreement({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.termsUrl = termsOfServiceUrl,
    this.privacyUrl = privacyPolicyUrl,
  });

  @override
  State<TermsAgreement> createState() => _TermsAgreementState();
}

class _TermsAgreementState extends State<TermsAgreement> {
  late final _openTerms = TapGestureRecognizer()
    ..onTap = () => _open(widget.termsUrl);
  late final _openPrivacy = TapGestureRecognizer()
    ..onTap = () => _open(widget.privacyUrl);

  @override
  void dispose() {
    _openTerms.dispose();
    _openPrivacy.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = TextStyle(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    final error = widget.errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: widget.value,
              onChanged: (value) => widget.onChanged(value ?? false),
              isError: error != null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: link,
                        recognizer: _openTerms,
                      ),
                      const TextSpan(text: ' and the '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: link,
                        recognizer: _openPrivacy,
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 2),
            child: Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
