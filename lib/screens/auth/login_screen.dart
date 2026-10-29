import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../services/app_prefs.dart';
import '../../services/login_prefs.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/auth_hero.dart';
import '../../widgets/auth/auth_link.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';
import '../../widgets/social_icon_row.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Connexion email/mot de passe + Google Sign-In + biométrie (BF2).
///
/// - l'email peut être mémorisé (« Se souvenir de moi »), jamais le mot de passe ;
/// - le domaine académique est proposé en un tap quand il manque ;
/// - le bouton biométrique n'apparaît que s'il y a une session à rouvrir et que
///   la préférence « déverrouillage biométrique » est active ;
/// - chaque erreur propose la suite logique (réessayer, réinitialiser…).
class LoginScreen extends StatefulWidget {
  /// Stockage des préférences, injectable dans les tests.
  final LoginPrefs? prefs;

  /// Préférences de l'application ; à défaut, celles fournies par `Provider`
  /// (le déverrouillage biométrique est actif si aucune n'est disponible).
  final AppPrefs? appPrefs;

  const LoginScreen({super.key, this.prefs, this.appPrefs});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
  late final LoginPrefs _prefs = widget.prefs ?? HiveLoginPrefs();

  String? _error;
  String? _errorCode;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    final remembered = _prefs.rememberedEmail;
    if (remembered != null) _emailCtrl.text = remembered;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().checkBiometrics();
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _needsDomain {
    final v = _emailCtrl.text.trim();
    return v.isNotEmpty && !v.contains('@');
  }

  void _completeDomain() {
    final local = _emailCtrl.text.trim();
    _emailCtrl.text = '$local@${AppConstants.academicEmailDomain}';
    _emailCtrl.selection = TextSelection.collapsed(offset: _emailCtrl.text.length);
    setState(() {});
    _passwordFocus.requestFocus();
  }

  /// Une fois connecté, _RootRouter affiche AppShell : on referme les écrans
  /// d'auth empilés au-dessus de la racine.
  Future<void> _goHome() async {
    await _prefs.remember(_rememberMe ? Validators.normalizeEmail(_emailCtrl.text) : null);
    if (!mounted) return;
    TextInput.finishAutofillContext(); // propose d'enregistrer les identifiants
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _clearError() {
    if (_error != null) {
      setState(() {
        _error = null;
        _errorCode = null;
      });
    }
  }

  void _showError(AuthProvider auth) {
    setState(() {
      _error = auth.errorMessage;
      _errorCode = auth.errorCode;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    _clearError();
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(_emailCtrl.text, _passwordCtrl.text);
    if (!mounted) return;
    if (ok) {
      await _goHome();
    } else {
      _showError(auth);
    }
  }

  Future<void> _google() async {
    _clearError();
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithGoogle();
    if (!mounted) return;
    if (ok) {
      if (auth.status == AuthStatus.authenticated) await _goHome();
    } else if (auth.errorMessage != null) {
      _showError(auth);
    }
  }

  Future<void> _biometrics() async {
    _clearError();
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithBiometrics();
    if (!mounted) return;
    if (ok) {
      await _goHome();
    } else if (auth.errorMessage != null) {
      _showError(auth);
    }
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialEmail: _emailCtrl.text)),
    );
  }

  /// Suite proposée selon l'erreur : réessayer si le réseau a lâché,
  /// réinitialiser le mot de passe après trop de tentatives.
  AuthBannerAction? get _errorAction => switch (_errorCode) {
        'network-request-failed' => AuthBannerAction('Réessayer', _submit),
        'too-many-requests' => AuthBannerAction('Réinitialiser le mot de passe', _openForgotPassword),
        _ => null,
      };

  bool get _biometricEnabled {
    final prefs = widget.appPrefs ?? context.read<AppPrefs?>();
    return prefs?.biometricUnlock ?? true;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final t = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final canPop = Navigator.of(context).canPop();

    return HeroSheetScaffold(
      hero: const AuthHero(
        title: 'Bon retour',
        subtitle: 'Connecte-toi avec ton email académique',
        icon: Icons.lock_open_rounded,
      ),
      heroLeading: canPop
          ? RoundIconButton(
              style: RoundButtonStyle.onPhoto,
              icon: Icons.arrow_back_rounded,
              tooltip: 'Retour',
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthTextField(
                  label: 'Email académique',
                  icon: Icons.mail_outline_rounded,
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  validator: Validators.email,
                  onChanged: (_) => setState(() {
                    _error = null;
                    _errorCode = null;
                  }),
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.topLeft,
                  child: _needsDomain
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ActionChip(
                              avatar: Icon(Icons.auto_fix_high_rounded, size: 16, color: t.onPrimarySoft),
                              label: const Text('Compléter avec @${AppConstants.academicEmailDomain}'),
                              labelStyle: textTheme.bodySmall?.copyWith(color: t.onPrimarySoft),
                              backgroundColor: t.primarySoft,
                              side: BorderSide.none,
                              onPressed: _completeDomain,
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Mot de passe',
                  icon: Icons.lock_outline_rounded,
                  controller: _passwordCtrl,
                  focusNode: _passwordFocus,
                  isPassword: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: Validators.loginPassword,
                  onChanged: (_) => _clearError(),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 8),
                // Wrap (et non Row) : sur un écran étroit ou avec une grande
                // police, le lien passe à la ligne au lieu de déborder.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _RememberMe(
                      value: _rememberMe,
                      onChanged: (v) => setState(() => _rememberMe = v),
                    ),
                    AuthLink(label: 'Mot de passe oublié ?', onPressed: _openForgotPassword),
                  ],
                ),
                const SizedBox(height: 16),
                AuthErrorBanner(message: _error, onClose: _clearError, action: _errorAction),
                PillButton(
                  label: 'Se connecter',
                  icon: Icons.arrow_forward_rounded,
                  isLoading: auth.isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 28),
                SocialIconRow(
                  items: [
                    SocialIconItem(
                      tooltip: 'Continuer avec Google',
                      onPressed: auth.isLoading ? null : _google,
                      child: const _GoogleMark(),
                    ),
                    if (auth.canUnlockWithBiometrics && _biometricEnabled)
                      SocialIconItem(
                        tooltip: 'Déverrouiller par biométrie',
                        icon: Icons.fingerprint_rounded,
                        onPressed: auth.isLoading ? null : _biometrics,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: textTheme.bodyMedium,
                        children: [
                          const TextSpan(text: 'Pas encore de compte ? '),
                          TextSpan(text: 'Créer un compte', style: AuthLink.style(context, weight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Case « Se souvenir de moi » (email uniquement, jamais le mot de passe).
/// La case suit le thème ; la ligne entière est la zone de toucher (48 dp).
class _RememberMe extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _RememberMe({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            Text('Se souvenir de moi', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// Monogramme « G » du bouton rond Google.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Text(
      'G',
      style: Theme.of(context)
          .textTheme
          .headlineMedium
          ?.copyWith(color: AppTokens.of(context).textPrimary, height: 1),
    );
  }
}
