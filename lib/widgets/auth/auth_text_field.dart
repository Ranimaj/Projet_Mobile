import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';

/// Champ de formulaire avec libellé au-dessus, icône et (optionnel) bouton
/// afficher/masquer pour les mots de passe. Le fond, les bordures, les textes
/// d'aide et d'erreur viennent de l'`InputDecorationTheme` du thème.
class AuthTextField extends StatefulWidget {
  final String label;
  final String? hint;

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

  const AuthTextField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.hint,
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
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: widget.enabled ? t.textPrimary : t.textSecondary),
        ),
        const SizedBox(height: 6),
        TextFormField(
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
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helper,
            helperMaxLines: 2,
            errorMaxLines: 2,
            prefixIcon: Icon(widget.icon, size: 20, color: t.textSecondary),
            suffixIcon: widget.isPassword
                ? IconButton(
                    tooltip: _obscure ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
