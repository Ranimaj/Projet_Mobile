import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';
import 'round_icon_button.dart';

class FloatingNavItem {
  final IconData icon;
  final String label;
  const FloatingNavItem({required this.icon, required this.label});
}

/// Floating pill navigation bar: round icon buttons, the active one filled
/// with the primary colour. Centred, at most 480 dp wide.
class FloatingNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<FloatingNavItem> items;

  const FloatingNavBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              key: const Key('nav-pill'),
              height: 62,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(40),
                border: dark ? Border.all(color: t.outline) : null,
                boxShadow: dark ? null : t.navShadow,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Semantics(
                      label: items[i].label,
                      selected: i == index,
                      button: true,
                      enabled: true,
                      excludeSemantics: true,
                      onTap: () => onChanged(i),
                      child: RoundIconButton(
                        icon: items[i].icon,
                        tooltip: items[i].label,
                        size: 46,
                        style: i == index
                            ? RoundButtonStyle.primary
                            : RoundButtonStyle.surface,
                        background: i == index ? null : Colors.transparent,
                        onPressed: () => onChanged(i),
                      ),
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
