import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_failure.dart';
import '../../core/utils/validators.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/section_card.dart';
import '../auth/otp_verification_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';

/// Gestion des Utilisateurs — écran Profil (BF2/BF3) : identité, badges de
/// vérification, sécurité, mode hors-ligne, export et suppression RGPD.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Le profil est une route poussée au-dessus de la racine : une fois la
  /// session fermée, on la referme pour laisser _RootRouter afficher l'écran
  /// visiteur (sinon l'écran resterait affiché sans utilisateur).
  Future<void> _logout(BuildContext context) async {
    final ok = await context.read<AuthProvider>().logout();
    if (ok && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _ProfileHeader(user: user, emailVerified: auth.emailVerified),
            const OfflineBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!auth.emailVerified) ...[
                    const _EmailVerificationBanner(),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      _StatTile(
                        label: 'Note moy.',
                        value: user.ratingCount > 0
                            ? user.ratingAverage.toStringAsFixed(1)
                            : '—',
                      ),
                      const SizedBox(width: 10),
                      _StatTile(label: 'Avis', value: '${user.ratingCount}'),
                      const SizedBox(width: 10),
                      _StatTile(
                          label: 'Membre depuis',
                          value: '${user.createdAt.year}'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SectionCard(
                    title: 'Compte',
                    children: [
                      SettingsTile(
                        icon: Icons.edit_rounded,
                        label: 'Modifier mes informations',
                        subtitle: 'Photo, nom, filière, compétences',
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const EditProfileScreen())),
                      ),
                      if (auth.hasPasswordProvider) ...[
                        SettingsTile(
                          icon: Icons.lock_reset_rounded,
                          label: 'Changer le mot de passe',
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const ChangePasswordScreen())),
                        ),
                      ],
                      SettingsTile(
                        icon: Icons.phone_iphone_rounded,
                        label: 'Numéro de téléphone',
                        subtitle: user.phoneNumber ?? 'Aucun numéro vérifié',
                        trailing: _Pill(
                          label:
                              user.isPhoneVerified ? 'Vérifié' : 'À vérifier',
                          positive: user.isPhoneVerified,
                        ),
                        onTap: () => _verifyPhone(context, user),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SectionCard(
                    title: 'Sécurité',
                    children: [
                      SettingsTile(
                        icon: Icons.shield_rounded,
                        label: 'Authentification à deux facteurs',
                        subtitle: 'Protection renforcée de ton compte',
                        trailing: Switch.adaptive(
                          value: user.twoFactorEnabled,
                          onChanged: auth.isLoading
                              ? null
                              : (v) => context
                                  .read<AuthProvider>()
                                  .updateProfile(
                                      user.copyWith(twoFactorEnabled: v)),
                        ),
                      ),
                      Consumer<ConnectivityProvider>(
                        builder: (context, connectivity, _) => SettingsTile(
                          icon: connectivity.isOnline
                              ? Icons.wifi_rounded
                              : Icons.wifi_off_rounded,
                          label: 'Mode hors-ligne',
                          subtitle: connectivity.pendingActionsCount > 0
                              ? '${connectivity.pendingActionsCount} action(s) en attente'
                              : 'Tes actions sont synchronisées automatiquement',
                          trailing: _Pill(
                            label: connectivity.isOnline ? 'En ligne' : 'Actif',
                            positive: connectivity.isOnline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SectionCard(
                    title: 'Données & confidentialité',
                    children: [
                      SettingsTile(
                        icon: Icons.download_rounded,
                        label: 'Exporter mes données (RGPD)',
                        subtitle: 'Copie JSON de ton profil et de ton compte',
                        onTap: () => _exportData(context),
                      ),
                      SettingsTile(
                        icon: Icons.delete_forever_rounded,
                        label: 'Supprimer mon compte',
                        color: AppColors.danger,
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => ChangeNotifierProvider.value(
                            value: context.read<AuthProvider>(),
                            child: const _DeleteAccountDialog(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  FilledButton.tonalIcon(
                    onPressed: auth.isLoading ? null : () => _logout(context),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: AppColors.danger.withValues(alpha: 0.1),
                      foregroundColor: AppColors.danger,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Déconnexion'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyPhone(BuildContext context, AppUser user) async {
    final phone = await showDialog<String>(
      context: context,
      builder: (_) => _PhoneDialog(initialPhone: user.phoneNumber ?? ''),
    );
    if (phone == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) =>
              OtpVerificationScreen(phone: phone, allowSkip: false)),
    );
  }

  Future<void> _exportData(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    Map<String, dynamic> data;
    try {
      data = await auth.exportMyData();
    } on AuthFailure catch (e) {
      if (context.mounted) showAuthSnack(context, e.message);
      return;
    }
    if (!context.mounted) return;
    final json = const JsonEncoder.withIndent('  ').convert(data);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mes données'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceTone,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                json,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              showAuthSnack(context, 'Données copiées dans le presse-papiers.',
                  isError: false);
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copier'),
          ),
        ],
      ),
    );
  }
}

// --- En-tête -----------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  final AppUser user;
  final bool emailVerified;
  const _ProfileHeader({required this.user, required this.emailVerified});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final details = [user.major, user.year]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');

    // Maquette « Gestion Utilisateurs » : en-tête clair, titre sombre, avatar
    // cerclé du dégradé violet, nom + coche, filière, puce de statut.
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.paddingOf(context).top + 12, 20, 8),
      color: AppColors.background,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Mon profil', style: text.headlineMedium),
          ),
          const SizedBox(height: 20),
          Container(
            width: 104,
            height: 104,
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
                shape: BoxShape.circle, gradient: AppColors.brandGradient),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.background),
              child: CircleAvatar(
                backgroundColor: AppColors.primary,
                backgroundImage: user.photoUrl == null
                    ? null
                    : CachedNetworkImageProvider(user.photoUrl!),
                child: user.photoUrl == null
                    ? Text(
                        user.initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  user.fullName,
                  textAlign: TextAlign.center,
                  style: text.displayMedium?.copyWith(fontSize: 24),
                ),
              ),
              if (user.isVerifiedStudent) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded,
                    size: 20, color: AppColors.primary),
              ],
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(details, style: text.bodyMedium),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _Badge(
                icon: user.isVerifiedStudent
                    ? Icons.verified_rounded
                    : Icons.hourglass_top_rounded,
                label: user.isVerifiedStudent
                    ? 'Étudiant vérifié'
                    : 'Vérification en attente',
                highlighted: user.isVerifiedStudent,
              ),
              if (emailVerified)
                const _Badge(
                    icon: Icons.mark_email_read_rounded,
                    label: 'Email vérifié',
                    highlighted: true),
              if (user.isPhoneVerified)
                const _Badge(
                    icon: Icons.phone_android_rounded,
                    label: 'Téléphone vérifié',
                    highlighted: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// Puce de statut : verte quand acquis (maquette « Étudiant vérifié »),
/// ambre tant que c'est en attente.
class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;
  const _Badge(
      {required this.icon, required this.label, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? AppColors.successTint : const Color(0xFFFEF3C7);
    final fg = highlighted ? AppColors.successInk : const Color(0xFF92400E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

// --- Bandeau email non vérifié ------------------------------------------------

class _EmailVerificationBanner extends StatefulWidget {
  const _EmailVerificationBanner();

  @override
  State<_EmailVerificationBanner> createState() =>
      _EmailVerificationBannerState();
}

class _EmailVerificationBannerState extends State<_EmailVerificationBanner>
    with WidgetsBindingObserver {
  Timer? _ticker;
  Timer? _autoCheck;

  /// Intervalle de re-vérification silencieuse tant que l'email n'est pas
  /// confirmé : l'utilisateur clique sur le lien dans sa boîte mail et le
  /// badge se met à jour tout seul, sans revenir appuyer sur « J'ai vérifié ».
  static const Duration autoCheckEvery = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTicker();
    _autoCheck = Timer.periodic(autoCheckEvery, (_) => _silentCheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _autoCheck?.cancel();
    super.dispose();
  }

  /// Retour dans l'app (après être allé cliquer sur le lien) : on revérifie.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _silentCheck();
  }

  Future<void> _silentCheck() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.isLoading || auth.emailVerified) return;
    await auth.refreshEmailVerification(silent: true);
  }

  /// Rafraîchit le compte à rebours tant qu'un délai de renvoi est en cours.
  void _syncTicker() {
    final auth = context.read<AuthProvider>();
    if (auth.canResendVerification) {
      _ticker?.cancel();
      _ticker = null;
    } else {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (context.read<AuthProvider>().canResendVerification) _syncTicker();
      });
    }
  }

  Future<void> _resend() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.resendVerificationEmail();
    if (!mounted) return;
    showAuthSnack(
      context,
      ok
          ? 'Email de vérification renvoyé.'
          : (auth.errorMessage ?? 'Envoi impossible.'),
      isError: !ok,
    );
    _syncTicker();
  }

  Future<void> _check() async {
    final auth = context.read<AuthProvider>();
    final verified = await auth.refreshEmailVerification();
    if (!mounted) return;
    if (!verified) {
      showAuthSnack(
          context,
          auth.errorMessage ??
              'Email toujours non vérifié. Clique sur le lien reçu.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final left = auth.verificationCooldownLeft.inSeconds;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mark_email_unread_outlined,
                  size: 18, color: AppColors.accent2),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Email non vérifié',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF9A3412)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Clique sur le lien reçu par email : ce bandeau disparaîtra tout seul.',
            style:
                TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF9A3412)),
          ),
          // Wrap plutôt que Row : avec le compte à rebours, les deux boutons
          // ne tiennent pas toujours sur une ligne en petite largeur.
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: auth.isLoading || left > 0 ? null : _resend,
                child: Text(left > 0 ? 'Renvoyer ($left s)' : 'Renvoyer'),
              ),
              TextButton(
                onPressed: auth.isLoading ? null : _check,
                child: const Text('J\'ai vérifié'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Petits composants ----------------------------------------------------------

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [AppColors.cardShadow],
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool positive;
  const _Pill({required this.label, required this.positive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: positive ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: positive ? const Color(0xFF065F46) : const Color(0xFF92400E),
        ),
      ),
    );
  }
}

// --- Dialogues -------------------------------------------------------------------

class _PhoneDialog extends StatefulWidget {
  final String initialPhone;
  const _PhoneDialog({required this.initialPhone});

  @override
  State<_PhoneDialog> createState() => _PhoneDialogState();
}

class _PhoneDialogState extends State<_PhoneDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _ctrl = TextEditingController(text: widget.initialPhone);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, Validators.normalizePhone(_ctrl.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vérifier mon numéro'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Un code à 6 chiffres te sera envoyé par SMS.',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 14),
            AuthTextField(
              label: 'Numéro de téléphone',
              hint: '20 123 456',
              icon: Icons.phone_outlined,
              controller: _ctrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              validator: Validators.phone,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: const Text('Envoyer le code')),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final auth = context.read<AuthProvider>();
    if (auth.hasPasswordProvider && !_formKey.currentState!.validate()) return;
    final ok = await auth.deleteAccount(
      password: auth.hasPasswordProvider ? _passwordCtrl.text : null,
    );
    if (!mounted) return;
    if (ok) {
      // Ferme le dialogue ET l'écran profil (route empilée au-dessus de la
      // racine) : _RootRouter affiche alors l'écran visiteur.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() => _error = auth.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return AlertDialog(
      title: const Text('Supprimer le compte'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cette action est irréversible : ton profil, tes annonces et tes candidatures seront supprimés.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (auth.hasPasswordProvider) ...[
              const SizedBox(height: 14),
              AuthTextField(
                label: 'Confirme avec ton mot de passe',
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                controller: _passwordCtrl,
                isPassword: true,
                autofocus: true,
                textInputAction: TextInputAction.done,
                validator: Validators.loginPassword,
                onSubmitted: (_) => _confirm(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: auth.isLoading ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: auth.isLoading ? null : _confirm,
          child: auth.isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Supprimer définitivement'),
        ),
      ],
    );
  }
}
