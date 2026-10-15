import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../widgets/offline_banner.dart';
import 'edit_profile_screen.dart';

/// Gestion des Utilisateurs — écran Profil (BF2/BF3) : identité, badge de
/// vérification, sécurité/2FA, mode hors-ligne, suppression RGPD.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const OfflineBanner(),
              const SizedBox(height: 18),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(user.initials,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(user.fullName, style: Theme.of(context).textTheme.titleLarge),
                  if (user.isVerifiedStudent) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified_rounded, size: 18, color: AppColors.success),
                  ],
                ],
              ),
              Text(
                [user.major, user.year].where((e) => e != null && e.isNotEmpty).join(' \u00b7 '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: user.isVerifiedStudent ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  user.isVerifiedStudent ? 'Étudiant vérifié' : 'Vérification en attente',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: user.isVerifiedStudent ? const Color(0xFF065F46) : const Color(0xFF92400E),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _StatTile(label: 'Note moy.', value: user.ratingCount > 0 ? user.ratingAverage.toStringAsFixed(1) : '—'),
                  const SizedBox(width: 10),
                  _StatTile(label: 'Avis', value: '${user.ratingCount}'),
                  const SizedBox(width: 10),
                  _StatTile(label: 'Membre depuis', value: '${user.createdAt.year}'),
                ],
              ),
              const SizedBox(height: 22),
              _MenuCard(children: [
                _MenuTile(
                  icon: Icons.edit_rounded,
                  label: 'Modifier mes informations',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                ),
                _MenuTile(
                  icon: Icons.shield_rounded,
                  label: 'Sécurité & authentification 2FA',
                  trailing: Switch(
                    value: user.twoFactorEnabled,
                    onChanged: (v) => context
                        .read<AuthProvider>()
                        .updateProfile(user.copyWith(twoFactorEnabled: v)),
                  ),
                  onTap: null,
                ),
                _MenuTile(
                  icon: Icons.download_rounded,
                  label: 'Exporter mes données (RGPD)',
                  onTap: () async {
                    await context.read<AuthProvider>().exportMyData();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Export généré.')));
                    }
                  },
                ),
                Consumer<ConnectivityProvider>(
                  builder: (context, connectivity, _) => _MenuTile(
                    icon: Icons.wifi_rounded,
                    label: 'Mode hors-ligne',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: connectivity.isOnline ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        connectivity.isOnline ? 'En ligne' : 'Actif',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: connectivity.isOnline ? const Color(0xFF065F46) : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                    onTap: null,
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.read<AuthProvider>().logout(),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Déconnexion'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => _confirmDelete(context),
                child: const Text('Supprimer mon compte', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le compte'),
        content: const Text(
            'Cette action est irréversible. Toutes vos données personnelles seront supprimées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AuthProvider>().deleteAccount();
            },
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _MenuTile({required this.icon, required this.label, this.trailing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: AppColors.textSecondary),
      title: Text(label, style: const TextStyle(fontSize: 13.5)),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: onTap,
    );
  }
}
