import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_tokens.dart';

/// Round avatar: photo when [photoUrl] is set, otherwise white initials on the
/// primary colour. [verified] adds a small check badge.
class InitialsAvatar extends StatelessWidget {
  final String initials;
  final String? photoUrl;
  final double size;
  final bool verified;
  final VoidCallback? onTap;

  const InitialsAvatar({
    super.key,
    required this.initials,
    this.photoUrl,
    this.size = 42,
    this.verified = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final initialsWidget = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
      child: Text(
        initials,
        maxLines: 1,
        style: (size >= 64 ? textTheme.headlineMedium! : textTheme.titleSmall!).copyWith(color: Colors.white),
      ),
    );
    final url = photoUrl;
    final circle = url == null || url.isEmpty
        ? initialsWidget
        : ClipOval(
            child: CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => initialsWidget,
              errorWidget: (_, __, ___) => initialsWidget,
            ),
          );

    Widget avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        if (verified)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              key: const Key('verified-badge'),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: t.primary,
                shape: BoxShape.circle,
                border: Border.all(color: t.surface, width: 2),
              ),
              child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
            ),
          ),
      ],
    );

    if (onTap == null) return avatar;
    final hit = size < 48 ? 48.0 : size;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap!();
        },
        child: SizedBox(width: hit, height: hit, child: Center(child: avatar)),
      ),
    );
  }
}
