import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';

/// Barre à 4 segments indiquant la robustesse du mot de passe saisi
/// (danger, warning puis success selon le score).
class PasswordStrengthMeter extends StatelessWidget {
  final String password;
  const PasswordStrengthMeter({super.key, required this.password});

  static const _labels = ['', 'Faible', 'Moyen', 'Bon', 'Excellent'];

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final score = Validators.passwordStrength(password);
    final color = switch (score) {
      <= 1 => t.danger,
      2 => t.warning,
      _ => t.success,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 4,
                margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
                decoration: BoxDecoration(
                  color: i < score ? color : t.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
        if (score > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Robustesse : ${_labels[score]}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.textSecondary, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}
