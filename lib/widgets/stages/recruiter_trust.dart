import 'package:flutter/material.dart';

import '../trust_badge.dart';

/// Nom et score de confiance du recruteur d'une offre.
class RecruiterTrust extends StatelessWidget {
  const RecruiterTrust({super.key, required this.recruiterId, this.loader});

  final String recruiterId;

  /// Charge le profil du recruteur (tests).
  final PublicUserLoader? loader;

  @override
  Widget build(BuildContext context) {
    return UserTrust(
      userId: recruiterId,
      loader: loader,
      builder: (context, trust, recruiter) => trust == null
          ? const SizedBox.shrink()
          : Padding(
              key: const Key('recruiter-trust'),
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Publiée par ${recruiter!.fullName}', style: Theme.of(context).textTheme.bodyMedium),
                  FittedBox(fit: BoxFit.scaleDown, child: TrustBadge(trust: trust)),
                ],
              ),
            ),
    );
  }
}
