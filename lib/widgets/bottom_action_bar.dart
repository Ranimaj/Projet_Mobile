import 'package:flutter/material.dart';
import '../core/constants/layout.dart';
import '../core/theme/app_tokens.dart';

/// Height of a bar holding two stacked 52 dp [PillButton]s: 16 dp paddings,
/// 8 dp gap (safe-area inset not included).
const double kBottomActionBarTwoRowHeight = 16 + 52 + 8 + 52 + 16;

/// Fixed bar holding the primary actions of a screen: surface fill, rounded top
/// corners and the nav shadow (outlined instead in dark mode).
class BottomActionBar extends StatelessWidget {
  final Widget child;
  const BottomActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: t.navShadow,
        border: Theme.of(context).brightness == Brightness.dark
            ? Border(top: BorderSide(color: t.outline))
            : null,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(kPagePadding, 16, kPagePadding, 16),
          child: child,
        ),
      ),
    );
  }
}
