import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';

/// One settings line: icon in a soft circle, title, optional subtitle and a
/// trailing widget (a chevron by default when [onTap] is set).
class SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  /// Optional icon tint (used by `SettingsTile`); ignored when [destructive].
  final Color? iconColor;

  /// Optional title tint (used by `SettingsTile`); ignored when [destructive].
  final Color? titleColor;

  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final tint = destructive ? t.danger : (iconColor ?? t.primary);
    final titleTint = destructive ? t.danger : (titleColor ?? t.textPrimary);
    final end = trailing ??
        (onTap == null
            ? null
            : Icon(Icons.chevron_right_rounded,
                size: 22, color: t.textSecondary));

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration:
                  BoxDecoration(color: t.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: text.titleSmall!.copyWith(color: titleTint)),
                  if (subtitle != null)
                    Text(subtitle!, style: text.labelMedium),
                ],
              ),
            ),
            if (end != null) ...[const SizedBox(width: 8), end],
          ],
        ),
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// Muted rounded container grouping [SettingRow]s with 1 px dividers and an
/// optional title above. Set [dividers] to false (and a [padding]) to host
/// arbitrary content such as form fields.
class SettingGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool dividers;

  const SettingGroup({
    super.key,
    this.title,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.dividers = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (dividers && i > 0) {
        rows.add(
            Divider(height: 1, thickness: 1, indent: 60, color: t.outline));
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(title!, style: Theme.of(context).textTheme.titleSmall),
          ),
        Container(
          key: const Key('group-fill'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: t.surfaceMuted, borderRadius: BorderRadius.circular(16)),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: padding,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows),
            ),
          ),
        ),
      ],
    );
  }
}
