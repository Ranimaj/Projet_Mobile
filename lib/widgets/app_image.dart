import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/local_photo_store.dart';

/// Image d'après sa référence en base : fichier sur le téléphone (cas
/// normal), image embarquée (`asset:...`) ou URL web (photos de
/// démonstration, liens externes).
class AppImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext context)? placeholder;
  final Widget Function(BuildContext context)? error;

  const AppImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    Widget onError(BuildContext c) => error?.call(c) ?? const SizedBox.shrink();
    if (isAssetImage(url)) {
      return Image.asset(assetPathOf(url),
          width: width, height: height, fit: fit, errorBuilder: (c, _, __) => onError(c));
    }
    if (isLocalImage(url)) {
      return Image.file(File(url), width: width, height: height, fit: fit, errorBuilder: (c, _, __) => onError(c));
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      placeholder: placeholder == null ? null : (c, _) => placeholder!(c),
      errorWidget: (c, _, __) => onError(c),
    );
  }
}

/// [ImageProvider] pour la même référence (fonds, `CircleAvatar`...).
ImageProvider appImageProvider(String url) {
  if (isAssetImage(url)) return AssetImage(assetPathOf(url));
  if (isLocalImage(url)) return FileImage(File(url));
  return CachedNetworkImageProvider(url);
}
