import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';

/// Barre à 4 segments indiquant la robustesse du mot de passe saisi.
///
/// [onDark] adapte la palette à un fond dégradé (segments vides blancs
/// translucides, teintes pastel lisibles sur bleu).
class PasswordStrengthMeter extends StatelessWidget {
  final String password;
  final bool onDark;
  const PasswordStrengthMeter({super.key, required this.password, this.onDark = false});

  static const _labels = ['', 'Faible', 'Moyen', 'Bon', 'Excellent'];

  @override
  Widget build(BuildContext context) {
    final score = Validators.passwordStrength(password);
    final color = onDark
        ? switch (score) {
            <= 1 => const Color(0xFFFFB4B4),
            2 => const Color(0xFFFFE08A),
            3 => Colors.white,
            _ => const Color(0xFFB9F6CA),
          }
        : switch (score) {
            <= 1 => AppColors.danger,
            2 => AppColors.warning,
            3 => AppColors.primary2,
            _ => AppColors.success,
          };
    final empty = onDark ? Colors.white.withValues(alpha: 0.3) : AppColors.surfaceTone;

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
                  color: i < score ? color : empty,
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
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}
