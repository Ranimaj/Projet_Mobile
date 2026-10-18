import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';

/// Saisie d'un code à usage unique : [length] cases visuelles pilotées par un
/// seul champ texte invisible (clavier numérique, collage et auto-remplissage
/// SMS fonctionnent naturellement).
///
/// Les cases sont des aplats (un ton au-dessus du fond), sans contour : la case
/// active est plus claire, les cases en erreur prennent la teinte d'erreur.
/// Quand [hasError] passe à `true`, les cases tremblent brièvement et le
/// téléphone vibre, pour signaler un code refusé sans lire de message.
class OtpInput extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final bool hasError;
  final bool enabled;

  /// `true` sur un champ de couleur sombre (encre blanche), `false` sur fond clair.
  final bool onDark;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;

  const OtpInput({
    super.key,
    required this.controller,
    this.length = Validators.otpLength,
    this.hasError = false,
    this.enabled = true,
    this.onDark = false,
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

  Color _fill({required bool active}) {
    if (widget.onDark) {
      if (widget.hasError) return AppColors.authErrorOnGradient.withValues(alpha: 0.28);
      if (!widget.enabled) return Colors.white.withValues(alpha: 0.08);
      return Colors.white.withValues(alpha: active ? 0.32 : 0.16);
    }
    if (widget.hasError) return AppColors.danger.withValues(alpha: 0.1);
    if (!widget.enabled) return AppColors.surfaceTone.withValues(alpha: 0.5);
    return active ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surfaceTone;
  }

  Color get _ink {
    if (widget.onDark) return widget.hasError ? AppColors.authErrorOnGradient : Colors.white;
    return widget.hasError ? AppColors.danger : AppColors.textPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;

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
                      color: _fill(active: active),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 90),
                      child: Text(
                        filled ? code[i] : '',
                        key: ValueKey(filled ? code[i] : ''),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 24, color: _ink),
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
