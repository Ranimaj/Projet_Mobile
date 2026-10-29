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

  // --- Boîtes Hive (cache / file d'attente offline) ---
  static const String hiveArticlesBox = 'articles_box';
  static const String hiveAnnoncesBox = 'annonces_box';
  static const String hiveEventsBox = 'events_box';
  static const String hiveJobsBox = 'jobs_box';
  static const String hiveUserBox = 'user_box';
  static const String hiveOfflineQueueBox = 'offline_queue_box';

  /// Petites préférences locales (email mémorisé sur l'écran de connexion…).
  static const String hivePrefsBox = 'prefs_box';

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
