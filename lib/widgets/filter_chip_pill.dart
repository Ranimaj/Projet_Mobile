import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_tokens.dart';

/// Selectable filter pill. 38 dp visual, 48 dp touch height.
class FilterChipPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  const FilterChipPill({super.key, required this.label, this.icon, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final fg = selected ? Colors.white : t.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              key: const Key('filter-fill'),
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? t.primary : t.surface,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: selected ? t.primary : t.outline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
