import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';

/// Saisie d'un code à usage unique : [length] cases visuelles pilotées par un
/// seul champ texte invisible (clavier numérique, collage et auto-remplissage
/// SMS fonctionnent naturellement).
///
/// Les cases sont `surfaceMuted` avec un contour `outline` : la case active
/// prend le contour `primary`, les cases en erreur le contour et le chiffre
/// `danger`.
/// Quand [hasError] passe à `true`, les cases tremblent brièvement et le
/// téléphone vibre, pour signaler un code refusé sans lire de message.
class OtpInput extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final bool hasError;
  final bool enabled;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;

  const OtpInput({
    super.key,
    required this.controller,
    this.length = Validators.otpLength,
    this.hasError = false,
    this.enabled = true,
    this.onCompleted,
    this.onChanged,
  });

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> with SingleTickerProviderStateMixin {
  final _focus = FocusNode();
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(covariant OtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasError && !oldWidget.hasError) {
      HapticFeedback.mediumImpact();
      if (!MediaQuery.of(context).disableAnimations) _shake.forward(from: 0);
    }
    // `autofocus` est ignoré tant que le champ est désactivé (code pas encore
    // envoyé) : on prend le focus dès qu'il devient actif, pour que le clavier
    // s'ouvre sans que l'utilisateur ait à taper sur les cases.
    if (widget.enabled && !oldWidget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _handleChange(String value) {
    widget.onChanged?.call(value);
    if (value.length == widget.length) widget.onCompleted?.call(value);
  }

  /// Oscillation amortie : 3 allers-retours de 8 px qui s'éteignent.
  double _shakeOffset(double t) {
    if (t == 0 || t == 1) return 0;
    const amplitude = 8.0;
    return amplitude * (1 - t) * math.sin(t * 3 * 2 * math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final t = AppTokens.of(context);

    return Semantics(
      label: 'Code de vérification à ${widget.length} chiffres',
      textField: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? () => _focus.requestFocus() : null,
        child: AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeOffset(_shake.value), 0),
            child: child,
          ),
          child: Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(widget.length, (i) {
                  final filled = i < code.length;
                  final active = _focus.hasFocus && i == code.length.clamp(0, widget.length - 1);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 46,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: widget.hasError
                            ? t.danger
                            : active && widget.enabled
                                ? t.primary
                                : t.outline,
                        width: active || widget.hasError ? 1.6 : 1,
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 90),
                      child: Text(
                        filled ? code[i] : '',
                        key: ValueKey(filled ? code[i] : ''),
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(color: widget.hasError ? t.danger : t.textPrimary),
                      ),
                    ),
                  );
                }),
              ),
              // Champ réel, invisible, étiré sur toute la zone.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    key: const Key('otp-field'),
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(widget.length),
                    ],
                    enableInteractiveSelection: false,
                    showCursor: false,
                    onChanged: _handleChange,
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
