import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';
import 'round_icon_button.dart';

/// Search field look-alike: a pill that opens the search when tapped, with an
/// optional filter button on the right.
class SearchPill extends StatelessWidget {
  final String hint;
  final VoidCallback? onTap;
  final VoidCallback? onFilter;

  const SearchPill({super.key, required this.hint, this.onTap, this.onFilter});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const Key('search-fill'),
      height: 52,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(26),
        border: dark ? Border.all(color: t.outline) : null,
        boxShadow: dark ? null : t.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding:
                EdgeInsets.only(left: 18, right: onFilter == null ? 18 : 2),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 22, color: t.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                if (onFilter != null)
                  RoundIconButton(
                    icon: Icons.tune_rounded,
                    tooltip: 'Filtrer',
                    style: RoundButtonStyle.soft,
                    onPressed: onFilter,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
