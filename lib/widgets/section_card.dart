import 'package:flutter/material.dart';
import 'setting_row.dart';

/// Grouped settings panel (profile, settings…). Visually a [SettingGroup]:
/// dividers appear only when every child is a settings row.
class SectionCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    this.title,
    required this.children,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    return SettingGroup(
      title: title,
      padding: padding,
      dividers: children.every((c) => c is SettingsTile || c is SettingRow),
      children: children,
    );
  }
}

/// Action row of a [SectionCard]: visually a [SettingRow]. A non-null [color]
/// tints the icon.
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: icon,
      title: label,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
      iconColor: color,
    );
  }
}
