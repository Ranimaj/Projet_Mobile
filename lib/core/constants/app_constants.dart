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

  // --- Catégories Événements ---
  static const List<String> eventCategories = [
    'Conférence',
    'Job Fair',
    'Sport',
    'Culture',
    'Associatif',
  ];

  // --- Types d'offres Stage & Emploi ---
  static const List<String> jobTypes = ['Stage', 'Emploi'];

  static const Duration debounceDuration = Duration(milliseconds: 400);
}
