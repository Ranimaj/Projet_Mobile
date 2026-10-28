import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';
import 'pill_button.dart';

/// Main CTA button (publish, apply, save…). Renders through
/// `PillButton(style: PillStyle.primary)`.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  /// Optional fill tint (module screens); defaults to the theme primary.
  final Color? color;

  /// Kept for compatibility; ignored (no gradients on buttons).
  final Gradient? gradient;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.color,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final button = PillButton(
      label: label,
      onPressed: onPressed,
      isLoading: isLoading,
      icon: icon,
    );
    final tint = color;
    if (tint == null) return button;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(extensions: [AppTokens.of(context).copyWith(primary: tint)]),
      child: button,
    );
  }
}
