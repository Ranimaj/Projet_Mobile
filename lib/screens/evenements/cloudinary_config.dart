/// Configuration Cloudinary pour les affiches d'événements.
///
/// Ce sont des IDENTIFIANTS PUBLICS, pas des secrets : un envoi « unsigned »
/// n'a besoin que du nom du cloud et du nom du preset (ils apparaissent de
/// toute façon dans chaque URL d'image). Le secret d'API (« API secret ») ne
/// doit JAMAIS se trouver dans l'app, dans Git ou dans les journaux.
///
/// Le preset « campusconnect_events » est configuré côté Cloudinary en mode
/// unsigned et range les fichiers dans le dossier campusconnect/events.
class CloudinaryConfig {
  CloudinaryConfig._();

  static const String cloudName = 'jmwc9h1o';
  static const String uploadPreset = 'campusconnect_events';

  /// Point d'envoi des images.
  static Uri get uploadUri => Uri.https('api.cloudinary.com', '/v1_1/$cloudName/image/upload');

  /// Début obligatoire d'une URL d'affiche acceptée (aussi vérifié par firestore.rules).
  static const String deliveryPrefix = 'https://res.cloudinary.com/$cloudName/';
}
