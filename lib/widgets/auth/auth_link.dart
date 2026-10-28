import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';

/// Text link of the auth screens: `primary`, underlined, at least 48 dp tall.
class AuthLink extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const AuthLink({super.key, required this.label, required this.onPressed});

  /// Style shared by every link, also used for the inline link of the login footer.
  static TextStyle? style(BuildContext context, {FontWeight? weight}) {
    final t = AppTokens.of(context);
    return Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: t.primary,
          fontWeight: weight ?? FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: t.primary,
        );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppTokens.of(context).primary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label, style: style(context)),
    );
  }
}
