import '../models/article_model.dart';
import 'local_photo_store.dart';

/// Articles de démonstration de Vente & Don : photos livrées avec l'app
/// (`assets/images/demo/`), donc visibles sur tous les téléphones même sans
/// Firebase Storage. Ajoutés au compte connecté par
/// [ArticleProvider.addDemoArticles].
class DemoArticle {
  final String title;
  final String description;
  final double? price;
  final String category;
  final String photo;
  final List<String> labels;

  const DemoArticle({
    required this.title,
    required this.description,
    required this.price,
    required this.category,
    required this.photo,
    required this.labels,
  });

  String get imageUrl => '${kAssetImagePrefix}assets/images/demo/$photo';
}

/// Position du campus ESPRIT Ghazela (remise en main propre).
const double kDemoLatitude = 36.8992;
const double kDemoLongitude = 10.1897;

const List<DemoArticle> kDemoArticles = [
  DemoArticle(
    title: 'Livre d\'algorithmique',
    description: 'Livre d\'algorithmique en très bon état, quelques notes au crayon. '
        'Idéal pour le module Algo de 1re année. Remise en main propre sur le campus.',
    price: 15,
    category: 'Livres',
    photo: 'livre_algo.jpg',
    labels: ['book', 'paper'],
  ),
  DemoArticle(
    title: 'Lampe de bureau LED',
    description: 'Lampe de bureau orientable, lumière LED, fonctionne parfaitement. '
        'Parfaite pour réviser le soir. Remise en main propre sur le campus.',
    price: 20,
    category: 'Mobilier',
    photo: 'lampe_bureau.jpg',
    labels: ['lamp', 'desk'],
  ),
  DemoArticle(
    title: 'Calculatrice scientifique',
    description: 'Calculatrice scientifique avec piles neuves, autorisée aux examens. '
        'Vendue avec son couvercle. Remise en main propre sur le campus.',
    price: 35,
    category: 'Électronique',
    photo: 'calculatrice.jpg',
    labels: ['calculator', 'gadget'],
  ),
  DemoArticle(
    title: 'Veste d\'hiver',
    description: 'Veste chaude taille M, portée un hiver, propre et sans défaut. '
        'Je la donne à qui en a besoin. Remise en main propre sur le campus.',
    price: null,
    category: 'Vêtements',
    photo: 'veste_hiver.jpg',
    labels: ['jacket', 'outerwear', 'clothing'],
  ),
];

/// Construit l'article (sans id) de [demo] pour [ownerId].
ArticleModel demoArticleFor(DemoArticle demo,
        {required String ownerId, required String ownerName, required DateTime createdAt}) =>
    ArticleModel(
      id: '',
      ownerId: ownerId,
      ownerName: ownerName,
      title: demo.title,
      description: demo.description,
      price: demo.price,
      category: demo.category,
      imageUrls: [demo.imageUrl],
      latitude: kDemoLatitude,
      longitude: kDemoLongitude,
      createdAt: createdAt,
      labels: demo.labels,
    );
