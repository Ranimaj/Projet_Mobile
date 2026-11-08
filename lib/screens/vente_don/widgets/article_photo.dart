import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../services/local_photo_store.dart';

/// Photo d'article : URL Storage (mise en cache) ou fichier encore sur le
/// téléphone quand l'article a été publié sans réseau.
class ArticlePhoto extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const ArticlePhoto({super.key, required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    Widget fallback(IconData icon) => ColoredBox(
          color: t.primarySoft,
          child: Center(child: Icon(icon, color: t.primary)),
        );
    if (isAssetImage(url)) {
      return Image.asset(
        assetPathOf(url),
        fit: fit,
        errorBuilder: (_, __, ___) => fallback(Icons.broken_image_outlined),
      );
    }
    if (isLocalImage(url)) {
      return Image.file(
        File(url),
        fit: fit,
        errorBuilder: (_, __, ___) => fallback(Icons.cloud_upload_outlined),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (_, __) => ColoredBox(color: t.primarySoft),
      errorWidget: (_, __, ___) => fallback(Icons.broken_image_outlined),
    );
  }
}
