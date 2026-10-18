import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/auth_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../services/login_prefs.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/gradient_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/social_icon_row.dart';
import '../../widgets/underline_text_field.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Connexion email/mot de passe + Google Sign-In + biométrie (BF2).
///
/// - l'email peut être mémorisé (« Se souvenir de moi »), jamais le mot de passe ;
/// - le domaine académique est proposé en un tap quand il manque ;
/// - le bouton biométrique n'apparaît que s'il y a une session à rouvrir ;
/// - chaque erreur propose la suite logique (réessayer, réinitialiser…).
class LoginScreen extends StatefulWidget {
  /// Stockage des préférences, injectable dans les tests.
  final LoginPrefs? prefs;

  const LoginScreen({super.key, this.prefs});

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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return GradientScaffold(
      title: 'Bon retour',
      subtitle: 'Connecte-toi avec ton email académique',
      icon: Icons.lock_open_rounded,
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UnderlineTextField(
                hint: 'Email académique',
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
                            avatar: const Icon(Icons.auto_fix_high_rounded, size: 16, color: Colors.white),
                            label: const Text('Compléter avec @${AppConstants.academicEmailDomain}'),
                            labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
                            backgroundColor: Colors.white.withValues(alpha: 0.18),
                            side: BorderSide.none,
                            onPressed: _completeDomain,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 18),
              UnderlineTextField(
                hint: 'Mot de passe',
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
              const SizedBox(height: 12),
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
                  TextButton(
                    onPressed: _openForgotPassword,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Mot de passe oublié ?', style: AuthTextStyles.link),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              AuthErrorBanner(message: _error, onClose: _clearError, action: _errorAction, onDark: true),
              Center(
                child: PillButton(
                  label: 'Se connecter',
                  icon: Icons.arrow_forward_rounded,
                  isLoading: auth.isLoading,
                  onPressed: _submit,
                ),
              ),
              const SizedBox(height: 32),
              SocialIconRow(
                items: [
                  SocialIconItem(
                    tooltip: 'Continuer avec Google',
                    onPressed: auth.isLoading ? null : _google,
                    child: const _GoogleMark(),
                  ),
                  if (auth.canUnlockWithBiometrics)
                    SocialIconItem(
                      tooltip: 'Déverrouiller par biométrie',
                      icon: Icons.fingerprint_rounded,
                      onPressed: auth.isLoading ? null : _biometrics,
                    ),
                ],
              ),
              const SizedBox(height: 30),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: RichText(
                    text: const TextSpan(
                      style: AuthTextStyles.footer,
                      children: [
                        TextSpan(text: 'Pas encore de compte ? '),
                        TextSpan(text: 'Créer un compte', style: AuthTextStyles.footerLink),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Case « Se souvenir de moi » : bordure blanche, remplie de blanc avec une
/// coche bleue quand elle est cochée (email uniquement, jamais le mot de passe).
class _RememberMe extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _RememberMe({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              side: const BorderSide(color: Colors.white, width: 1.6),
              fillColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.transparent,
              ),
              checkColor: AppColors.authGradientBottom,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            ),
          ),
          const SizedBox(width: 4),
          const Text('Se souvenir de moi', style: AuthTextStyles.small),
        ],
      ),
    );
  }
}

/// Monogramme « G » blanc pour le bouton rond Google.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, height: 1),
    );
  }
}
