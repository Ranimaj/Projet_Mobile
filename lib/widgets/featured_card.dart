import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';
import 'pill_button.dart';
import 'status_chip.dart';

class FeaturedMeta {
  final IconData icon;
  final String text;
  const FeaturedMeta(this.icon, this.text);
}

/// Large card with a photo under an orange gradient, white text and a dark
/// action pill ("À la une").
class FeaturedCard extends StatelessWidget {
  final String? imageUrl;
  final String chipLabel;
  final String title;
  final List<FeaturedMeta> meta;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTap;
  final double height;

  const FeaturedCard({
    super.key,
    this.imageUrl,
    required this.chipLabel,
    required this.title,
    required this.meta,
    required this.actionLabel,
    this.onAction,
    this.onTap,
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final url = imageUrl;
    Widget background = ColoredBox(color: t.primary);
    if (url != null) {
      background = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => ColoredBox(color: t.primary),
        errorWidget: (_, __, ___) => ColoredBox(color: t.primary),
      );
    }

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            background,
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    t.primary.withValues(alpha: 0.92),
                    t.primary.withValues(alpha: 0.55),
                    t.primary.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.45, 0.8],
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusChip(
                          label: chipLabel, style: StatusChipStyle.onPhoto),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                text.titleLarge!.copyWith(color: Colors.white)),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 2,
                              children: [
                                for (final m in meta)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(m.icon,
                                          size: 14, color: Colors.white),
                                      const SizedBox(width: 4),
                                      Text(m.text,
                                          style: text.labelMedium!
                                              .copyWith(color: Colors.white)),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          PillButton(
                            label: actionLabel,
                            onPressed: onAction,
                            style: PillStyle.dark,
                            expand: false,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
