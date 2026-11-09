import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/auth_hero.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../auth/otp_verification_screen.dart';

/// Double authentification : connexion depuis un appareil qui n'est pas
/// encore de confiance. L'accueil ne s'ouvre qu'après le code SMS, ou
/// l'accord donné depuis un appareil déjà connecté (« Mes appareils »).
class ConfirmDeviceScreen extends StatelessWidget {
  const ConfirmDeviceScreen({super.key});

  /// `+216 •• ••• 678` : seuls les 3 derniers chiffres restent visibles.
  static String maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return phone;
    return '•• ••• ${digits.substring(digits.length - 3)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final phone = auth.currentUser?.phoneNumber ?? '';

    return HeroSheetScaffold(
      hero: const AuthHero(
        title: 'Nouvel appareil',
        subtitle: 'Confirme que c\'est bien toi',
        icon: Icons.phonelink_lock_rounded,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'La double authentification est active sur ton compte et c\'est la première fois que tu '
              'te connectes depuis cet appareil.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Nous allons envoyer un code par SMS au ${maskPhone(phone)}.',
              style: text.bodyMedium?.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: 24),
            PillButton(
              key: const Key('confirm-device-sms'),
              label: 'Recevoir le code',
              icon: Icons.sms_outlined,
              onPressed: phone.isEmpty
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => OtpVerificationScreen(phone: phone, allowSkip: false),
                      )),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: t.surfaceMuted, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.devices_rounded, size: 20, color: t.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ou approuve cette connexion depuis un appareil déjà connecté : Profil › Mes appareils.',
                      style: text.bodyMedium?.copyWith(color: t.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('confirm-device-logout'),
              onPressed: auth.isLoading ? null : () => context.read<AuthProvider>().logout(),
              child: const Text('Annuler et se déconnecter'),
            ),
          ],
        ),
      ],
    );
  }
}
