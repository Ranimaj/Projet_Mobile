import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/auth_failure.dart';
import '../../core/utils/validators.dart';
import '../../models/user_model.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/job_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/app_prefs.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/initials_avatar.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/status_chip.dart';
import '../auth/otp_verification_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';

// Scrim over the cover photo (same pair as the visitor home).
const _scrimTop = Color(0x33000000);
const _scrimBottom = Color(0xCC000000);

/// How far the avatar pokes above the first child (it straddles the hero edge).
const double _avatarLift = 32;

/// Gestion des Utilisateurs — écran Profil (BF2/BF3) : identité, badges de
/// vérification, préférences, sécurité, mode hors-ligne, export et suppression
/// RGPD.
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

  void _edit(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const EditProfileScreen()));

  static String _details(AppUser user) => [user.major, user.year]
      .where((e) => e != null && e.isNotEmpty)
      .join(' · ');

  Future<void> _share(BuildContext context, AppUser user) async {
    final text =
        [user.fullName, _details(user)].where((e) => e.isNotEmpty).join(' · ');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    showAuthSnack(context, 'Profil copié', isError: false);
  }

  static String _themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Clair',
        ThemeMode.dark => 'Sombre',
        ThemeMode.system => 'Système',
      };

  void _pickTheme(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Consumer<ThemeProvider>(
        builder: (context, theme, _) => SafeArea(
          child: RadioGroup<ThemeMode>(
            groupValue: theme.mode,
            onChanged: (m) {
              if (m == null) return;
              theme.setMode(m);
              Navigator.pop(sheetContext);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: m,
                    title: Text(_themeLabel(m)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ({StatusChipStyle style, String label})? _cardChip(AppUser user) {
    if (user.isVerifiedStudent ||
        user.studentCard.status == StudentCardStatus.verified) {
      return (style: StatusChipStyle.success, label: 'Étudiant vérifié');
    }
    return switch (user.studentCard.status) {
      StudentCardStatus.pending => (
          style: StatusChipStyle.warning,
          label: 'Vérification en attente'
        ),
      StudentCardStatus.rejected => (
          style: StatusChipStyle.danger,
          label: 'Carte refusée'
        ),
      _ => null,
    };
  }

  String _cardSubtitle(AppUser user) => switch (_cardChip(user)?.label) {
        'Étudiant vérifié' => 'Ta carte est vérifiée',
        'Vérification en attente' => 'Vérification en cours',
        'Carte refusée' => 'Carte refusée : envoie-la à nouveau',
        _ => 'Ajoute ta carte pour être vérifié',
      };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final cardChip = _cardChip(user);
    final details = _details(user);
    final notices = context
        .watch<AnnonceProvider>()
        .items
        .where((a) => a.authorId == user.id)
        .length;
    final sales = context
        .watch<ArticleProvider>()
        .items
        .where((a) => a.ownerId == user.id)
        .length;
    final applications = context.watch<JobProvider>().myApplications.length;
    final prefs = context.read<AppPrefs>();
    final themeMode = context.watch<ThemeProvider>().mode;
    final since = DateFormat('MMM yyyy', 'fr_FR').format(user.createdAt);

    return HeroSheetScaffold(
      showHandle: false,
      contentLift: _avatarLift + 12,
      hero: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/cover_campus.jpg',
            fit: BoxFit.cover,
            cacheWidth: 1080,
            excludeFromSemantics: true,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [_scrimBottom, _scrimTop],
              ),
            ),
          ),
        ],
      ),
      heroLeading: Navigator.of(context).canPop()
          ? RoundIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Retour',
              style: RoundButtonStyle.onPhoto,
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      heroActions: [
        RoundIconButton(
          icon: Icons.ios_share_rounded,
          tooltip: 'Partager',
          style: RoundButtonStyle.onPhoto,
          onPressed: () => _share(context, user),
        ),
        RoundIconButton(
          icon: Icons.edit_rounded,
          tooltip: 'Modifier',
          style: RoundButtonStyle.onPhoto,
          onPressed: () => _edit(context),
        ),
      ],
      bottomBar: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text('Membre depuis $since', style: text.labelMedium),
          PillButton(
            label: 'Modifier le profil',
            onPressed: () => _edit(context),
          ),
        ],
      ),
      children: [
        SizedBox(
          height: 52,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: -_avatarLift,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: t.surface, width: 4),
                  ),
                  child: InitialsAvatar(
                    initials: user.initials,
                    photoUrl: user.photoUrl,
                    size: 64,
                    verified: user.isVerifiedStudent,
                  ),
                ),
              ),
              if (cardChip != null)
                Positioned(
                  right: 0,
                  top: 8,
                  child:
                      StatusChip(label: cardChip.label, style: cardChip.style),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(user.fullName,
            style: text.headlineMedium!.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            auth.emailVerified
                ? const StatusChip(
                    label: 'Email vérifié',
                    style: StatusChipStyle.success,
                    icon: Icons.mark_email_read_rounded)
                : const StatusChip(
                    label: 'Email à vérifier',
                    style: StatusChipStyle.warning,
                    icon: Icons.mark_email_unread_outlined),
            if (user.isPhoneVerified)
              const StatusChip(
                  label: 'Téléphone vérifié',
                  style: StatusChipStyle.success,
                  icon: Icons.phone_android_rounded),
          ],
        ),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(details,
              style: text.bodyMedium!.copyWith(color: t.textSecondary)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: StatTile(value: '$notices', label: 'Annonces')),
            const SizedBox(width: 10),
            Expanded(child: StatTile(value: '$sales', label: 'Ventes')),
            const SizedBox(width: 10),
            Expanded(
                child: StatTile(value: '$applications', label: 'Candidatures')),
          ],
        ),
        const SizedBox(height: 16),
        const OfflineBanner(),
        if (!auth.emailVerified) ...[
          const _EmailVerificationBanner(),
          const SizedBox(height: 16),
        ],
        SettingGroup(
          children: [
            SettingRow(
              icon: Icons.badge_rounded,
              title: 'Carte étudiant',
              subtitle: _cardSubtitle(user),
              // Branché sur l'écran de la carte par la tâche suivante.
              onTap: null,
            ),
            SettingRow(
              icon: Icons.fingerprint_rounded,
              title: 'Connexion biométrique',
              subtitle: 'Déverrouille l\'app avec ton empreinte ou ton visage',
              trailing: _BiometricSwitch(prefs: prefs),
            ),
            SettingRow(
              icon: Icons.brightness_6_rounded,
              title: 'Thème',
              subtitle: _themeLabel(themeMode),
              onTap: () => _pickTheme(context),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingGroup(
          title: 'Compte',
          children: [
            SettingRow(
              icon: Icons.edit_rounded,
              title: 'Modifier mes informations',
              subtitle: 'Photo, nom, filière, compétences',
              onTap: () => _edit(context),
            ),
            if (auth.hasPasswordProvider)
              SettingRow(
                icon: Icons.lock_reset_rounded,
                title: 'Changer le mot de passe',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen())),
              ),
            SettingRow(
              icon: Icons.phone_iphone_rounded,
              title: 'Numéro de téléphone',
              subtitle: user.phoneNumber ?? 'Aucun numéro vérifié',
              trailing: StatusChip(
                label: user.isPhoneVerified ? 'Vérifié' : 'À vérifier',
                style: user.isPhoneVerified
                    ? StatusChipStyle.success
                    : StatusChipStyle.warning,
              ),
              onTap: () => _verifyPhone(context, user),
            ),
            SettingRow(
              icon: Icons.download_rounded,
              title: 'Exporter mes données (RGPD)',
              subtitle: 'Copie JSON de ton profil et de ton compte',
              onTap: () => _exportData(context),
            ),
            SettingRow(
              icon: Icons.delete_forever_rounded,
              title: 'Supprimer mon compte',
              destructive: true,
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
        const SizedBox(height: 20),
        SettingGroup(
          title: 'Sécurité',
          children: [
            SettingRow(
              icon: Icons.shield_rounded,
              title: 'Authentification à deux facteurs',
              subtitle: 'Protection renforcée de ton compte',
              trailing: Switch.adaptive(
                value: user.twoFactorEnabled,
                onChanged: auth.isLoading
                    ? null
                    : (v) => context
                        .read<AuthProvider>()
                        .updateProfile(user.copyWith(twoFactorEnabled: v)),
              ),
            ),
            Consumer<ConnectivityProvider>(
              builder: (context, connectivity, _) => SettingRow(
                icon: connectivity.isOnline
                    ? Icons.wifi_rounded
                    : Icons.wifi_off_rounded,
                title: 'Mode hors-ligne',
                subtitle: connectivity.pendingActionsCount > 0
                    ? '${connectivity.pendingActionsCount} action(s) en attente'
                    : 'Tes actions sont synchronisées automatiquement',
                trailing: StatusChip(
                  label: connectivity.isOnline ? 'En ligne' : 'Actif',
                  style: connectivity.isOnline
                      ? StatusChipStyle.success
                      : StatusChipStyle.warning,
                ),
              ),
            ),
          ],
        ),
        if (user.role == UserRole.admin) ...[
          const SizedBox(height: 20),
          const SettingGroup(
            title: 'Administration',
            children: [
              // Branchés sur leurs écrans par les tâches d'administration.
              SettingRow(
                  icon: Icons.group_rounded,
                  title: 'Utilisateurs',
                  onTap: null),
              SettingRow(
                  icon: Icons.fact_check_rounded,
                  title: 'Cartes à vérifier',
                  onTap: null),
              SettingRow(
                  icon: Icons.insights_rounded,
                  title: 'Statistiques',
                  onTap: null),
            ],
          ),
        ],
        const SizedBox(height: 20),
        PillButton(
          label: 'Déconnexion',
          icon: Icons.logout_rounded,
          style: PillStyle.danger,
          onPressed: auth.isLoading ? null : () => _logout(context),
        ),
      ],
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
              color: AppTokens.of(ctx).surfaceMuted,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                json,
                style: Theme.of(ctx)
                    .textTheme
                    .bodyMedium!
                    .copyWith(fontFamily: 'monospace'),
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

/// Interrupteur de la connexion biométrique, persisté dans [AppPrefs].
class _BiometricSwitch extends StatefulWidget {
  final AppPrefs prefs;
  const _BiometricSwitch({required this.prefs});

  @override
  State<_BiometricSwitch> createState() => _BiometricSwitchState();
}

class _BiometricSwitchState extends State<_BiometricSwitch> {
  late bool _value = widget.prefs.biometricUnlock;

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: _value,
      onChanged: (v) {
        setState(() => _value = v);
        widget.prefs.setBiometricUnlock(v);
      },
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
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final left = auth.verificationCooldownLeft.inSeconds;
    final action = TextButton.styleFrom(minimumSize: const Size(48, 48));

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: t.warningSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mark_email_unread_outlined,
                  size: 18, color: t.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Email non vérifié',
                    style: text.titleSmall!.copyWith(color: t.warning)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Clique sur le lien reçu par email : ce bandeau disparaîtra tout seul.',
            style: text.bodyMedium!.copyWith(color: t.textPrimary),
          ),
          // Wrap plutôt que Row : avec le compte à rebours, les deux boutons
          // ne tiennent pas toujours sur une ligne en petite largeur.
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                style: action,
                onPressed: auth.isLoading || left > 0 ? null : _resend,
                child: Text(left > 0 ? 'Renvoyer ($left s)' : 'Renvoyer'),
              ),
              TextButton(
                style: action,
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
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium!
                      .copyWith(color: AppTokens.of(context).danger)),
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
          style: FilledButton.styleFrom(
              backgroundColor: AppTokens.of(context).danger),
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
