import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/theme/app_tokens.dart';

/// Loading placeholder with a soft shimmer (static when animations are off).
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;

  const SkeletonBox({super.key, this.width, this.height, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: t.surfaceMuted, borderRadius: BorderRadius.circular(radius)),
    );
    if (MediaQuery.of(context).disableAnimations) return box;
    return Shimmer.fromColors(baseColor: t.surfaceMuted, highlightColor: t.surface, child: box);
  }
}
