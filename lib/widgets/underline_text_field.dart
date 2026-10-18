import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/auth_text_styles.dart';

/// Champ « souligné » pour les écrans sur dégradé : icône blanche, texte
/// d'indication blanc, fin soulignement blanc (plus épais au focus), texte et
/// curseur blancs, erreur en rose pâle. Même API que `AuthTextField`.
class UnderlineTextField extends StatefulWidget {
  final String hint;

  /// Petit texte d'aide sous le champ (remplacé par l'erreur de validation).
  final String? helper;
  final IconData icon;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool isPassword;
  final bool autofocus;
  final bool enabled;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const UnderlineTextField({
    super.key,
    required this.hint,
    required this.icon,
    required this.controller,
    this.helper,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.isPassword = false,
    this.autofocus = false,
    this.enabled = true,
    this.focusNode,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<UnderlineTextField> createState() => _UnderlineTextFieldState();
}

class _UnderlineTextFieldState extends State<UnderlineTextField> {
  bool _obscure = true;

  static final _enabledBorder = UnderlineInputBorder(
    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.6), width: 1),
  );
  static const _focusedBorder = UnderlineInputBorder(
    borderSide: BorderSide(color: Colors.white, width: 2),
  );
  static const _errorBorder = UnderlineInputBorder(
    borderSide: BorderSide(color: AppColors.authErrorOnGradient, width: 1.4),
  );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      obscureText: widget.isPassword && _obscure,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      autofillHints: widget.autofillHints,
      autocorrect: !widget.isPassword,
      enableSuggestions: !widget.isPassword,
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      style: AuthTextStyles.input,
      cursorColor: Colors.white,
      decoration: InputDecoration(
        // On neutralise explicitement le thème global (champs remplis).
        filled: false,
        fillColor: Colors.transparent,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        hintText: widget.hint,
        hintStyle: AuthTextStyles.hint,
        helperText: widget.helper,
        helperStyle: AuthTextStyles.helper,
        helperMaxLines: 2,
        errorStyle: AuthTextStyles.fieldError,
        errorMaxLines: 2,
        prefixIcon: Icon(widget.icon, size: 22, color: Colors.white),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 24),
        suffixIcon: widget.isPassword
            ? IconButton(
                tooltip: _obscure ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                icon: Icon(
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
        border: _enabledBorder,
        enabledBorder: _enabledBorder,
        disabledBorder: _enabledBorder,
        focusedBorder: _focusedBorder,
        errorBorder: _errorBorder,
        focusedErrorBorder: _errorBorder,
      ),
    );
  }
}
