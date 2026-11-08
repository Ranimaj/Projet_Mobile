/// Constantes globales de l'application.
class AppConstants {
  AppConstants._();

  static const String appName = 'CampusConnect';

  // --- Collections Firestore ---
  static const String usersCollection = 'users';
  static const String articlesCollection = 'articles'; // Vente & Don
  static const String annoncesCollection = 'annonces'; // Annonces campus
  static const String eventsCollection = 'events'; // Événements
  static const String jobOffersCollection = 'job_offers'; // Stage & Emploi
  static const String applicationsCollection = 'applications';

  // --- Cache local SQLite : clé de collection de chaque module ---
  // (valeurs inchangées : ce sont les clés de la table cache_documents)
  static const String cacheArticlesKey = 'articles_box';
  static const String cacheAnnoncesKey = 'annonces_box';
  static const String cacheEventsKey = 'events_box';
  static const String cacheJobsKey = 'jobs_box';

  // Anciens noms, gardés comme alias pour que les providers des autres
  // modules (Vente & Don, Annonces, Stage & Emploi) n'aient pas à changer.
  static const String hiveArticlesBox = cacheArticlesKey;
  static const String hiveAnnoncesBox = cacheAnnoncesKey;
  static const String hiveJobsBox = cacheJobsKey;

  /// Domaine des emails académiques, proposé en complétion à la connexion.
  static const String academicEmailDomain = 'esprit.tn';

  // --- Catégories Vente & Don ---
  static const List<String> articleCategories = [
    'Livres',
    'Électronique',
    'Vêtements',
    'Mobilier',
    'Dons',
    'Autre',
  ];

  // --- Catégories Annonces ---
  static const List<String> annonceCategories = [
    'Officielle',
    'Perdu & Trouvé',
    'Générale',
  ];

  // --- Catégories Événements : voir lib/screens/evenements/event_categories.dart ---

  // --- Profil étudiant ---
  static const List<String> studyYears = [
    '1ère année',
    '2ème année',
    '3ème année',
    '4ème année',
    '5ème année',
    'Alumni',
  ];
  static const int maxSkills = 10;

  /// Campus par défaut des nouveaux profils.
  static const String defaultCampus = 'ESPRIT Ghazela';

  static const List<String> departments = [
    'Génie Informatique',
    'Génie Civil',
    'Génie Électromécanique',
    'Génie Télécom',
    'Génie Industriel',
    'Business',
    'Autre',
  ];

  // --- Types d'offres Stage & Emploi ---
  static const List<String> jobTypes = ['Stage', 'Emploi'];

  static const Duration debounceDuration = Duration(milliseconds: 400);
}
