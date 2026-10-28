import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';
import 'round_icon_button.dart';
import 'status_chip.dart';

/// Card with a photo on top (chip and heart overlaid), a title, and optional
/// meta / footer widgets below.
class PhotoCard extends StatelessWidget {
  final String? imageUrl;
  final IconData placeholderIcon;
  final StatusChip? chip;
  final bool showHeart;
  final bool favorite;
  final VoidCallback? onHeart;
  final String title;
  final Widget? meta;
  final Widget? footer;
  final VoidCallback? onTap;
  final double imageHeight;
  final double? width;

  const PhotoCard({
    super.key,
    this.imageUrl,
    this.placeholderIcon = Icons.image_outlined,
    this.chip,
    this.showHeart = false,
    this.favorite = false,
    this.onHeart,
    required this.title,
    this.meta,
    this.footer,
    this.onTap,
    this.imageHeight = 120,
    this.width,
  });

  Widget _placeholder(AppTokens t) => Container(
        key: const Key('photo-placeholder'),
        width: double.infinity,
        height: imageHeight,
        decoration: BoxDecoration(color: t.primarySoft),
        child: Icon(placeholderIcon, size: 36, color: t.primary),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final url = imageUrl;
    final image = url == null
        ? _placeholder(t)
        : CachedNetworkImage(
            imageUrl: url,
            width: double.infinity,
            height: imageHeight,
            fit: BoxFit.cover,
            placeholder: (_, __) => _placeholder(t),
            errorWidget: (_, __, ___) => _placeholder(t),
          );

    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(20),
        border: dark ? Border.all(color: t.outline) : null,
        boxShadow: dark ? null : t.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  image,
                  if (chip != null) Positioned(top: 10, left: 10, child: chip!),
                  if (showHeart)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: RoundIconButton(
                        icon: favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        tooltip: favorite
                            ? 'Retirer des favoris'
                            : 'Ajouter aux favoris',
                        style: RoundButtonStyle.onPhoto,
                        size: 34,
                        onPressed: onHeart,
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                    if (meta != null) ...[const SizedBox(height: 4), meta!],
                    if (footer != null) ...[const SizedBox(height: 8), footer!],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
