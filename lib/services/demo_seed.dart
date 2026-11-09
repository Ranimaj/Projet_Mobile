import 'dart:math';

import '../core/constants/app_constants.dart';
import '../core/utils/password_hasher.dart';
import '../models/annonce_model.dart';
import '../models/event_model.dart';
import '../models/job_offer_model.dart';
import '../models/user_model.dart';
import 'auth_service.dart';
import 'local_photo_store.dart' show kAssetImagePrefix;
import 'local_store.dart';

/// Données de démonstration écrites au premier lancement (base vide) :
///
/// - 6 comptes réels, mot de passe [password] : un admin, trois étudiants
///   dont la carte attend la vérification, un recruteur, et Jawher Khalifa
///   (profil complet, carte vérifiée) ;
/// - les contenus de la maquette : événements (« À la une » : Hackathon
///   ESPRIT 2026), annonces (2 officielles épinglées + 12 de Jawher), offres
///   de stage et d'emploi, 3 candidatures de Jawher ;
/// - ~2 350 comptes fictifs (profil seul, aucune connexion possible) pour
///   que l'écran Analytics affiche ~1 248 inscrits sur 30 jours (+12 %),
///   37 cartes en attente et la répartition 77 / 17 / 6 % par rôle.
///
/// Les articles Vente & Don vivent dans une autre base (ArticleDatabase) et
/// ne sont pas créés ici. Les photos sont des images embarquées
/// (`asset:assets/images/...`).
///
/// Identifiants fixes (`demo-…`) et tirages aléatoires à graine fixe : deux
/// premiers lancements donnent les mêmes données, à la date près (les dates
/// sont calculées par rapport à aujourd'hui).
class DemoSeed {
  DemoSeed({LocalStore? store, PasswordHasher? hasher, DateTime Function()? clock})
      : _store = store ?? LocalStore(),
        _hasher = hasher ?? PasswordHasher(),
        _clock = clock ?? DateTime.now;

  final LocalStore _store;
  final PasswordHasher _hasher;
  final DateTime Function() _clock;

  /// Mot de passe des 6 comptes de démonstration.
  static const String password = 'Campus2026!';

  static const String adminId = 'demo-admin';
  static const String amelId = 'demo-amel';
  static const String sarraId = 'demo-sarra';
  static const String youssefId = 'demo-youssef';
  static const String recruiterId = 'demo-recruteur';
  static const String jawherId = 'demo-jawher';

  /// Photo de carte étudiante factice (toutes les cartes déposées).
  static const String cardImage = '${kAssetImagePrefix}assets/images/cover_campus.jpg';

  static String _photo(String name) => '${kAssetImagePrefix}assets/images/onboarding/esprit_$name.jpg';

  /// Écrit les données de démonstration si la collection `users` est vide ;
  /// sinon ne fait rien.
  Future<void> ensureSeeded() async {
    if (_store.all(AppConstants.usersCollection).isNotEmpty) return;
    final now = _clock().toUtc();
    _now = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute, now.second);
    _rng = Random(2026);
    _pending.clear();

    _accounts();
    _jawherProfile();
    _events();
    _annonces();
    _jobs();
    _fakeAccounts();

    // Une transaction SQLite par collection. `users` en dernier : tant qu'il
    // est vide, un lancement interrompu reprend le remplissage au suivant (les
    // ids sont fixes, une collection déjà écrite est simplement remplacée).
    final users = _pending.remove(AppConstants.usersCollection);
    for (final e in _pending.entries) {
      await _store.setAll(e.key, e.value);
    }
    if (users != null) await _store.setAll(AppConstants.usersCollection, users);
    _pending.clear();
  }

  late DateTime _now;
  late Random _rng;
  /// collection → id → données, écrites d'un coup à la fin.
  final Map<String, Map<String, Map<String, dynamic>>> _pending = {};

  void _set(String collection, String id, Map<String, dynamic> data) =>
      _pending.putIfAbsent(collection, () => {})[id] = data;

  DateTime _ago({int days = 0, int hours = 0}) => _now.subtract(Duration(days: days, hours: hours));

  DateTime _ahead(int days, {int hour = 9}) {
    final d = _now.add(Duration(days: days));
    return DateTime.utc(d.year, d.month, d.day, hour);
  }

  // --- Comptes réels -----------------------------------------------------------

  static const _students = [
    (amelId, 'Amel Ben Salah'),
    (sarraId, 'Sarra Trabelsi'),
    (youssefId, 'Youssef Gharbi'),
  ];

  void _accounts() {
    // Une seule empreinte PBKDF2 pour les 6 comptes (même mot de passe
    // public) : le premier lancement reste rapide.
    final hash = _hasher.hash(password).toMap();
    final pendingCard = StudentCard.pending(imagePath: cardImage, submittedAt: _now);
    const skills = ['Flutter', 'Firebase'];
    final accounts = [
      (adminId, 'admin@esprit.tn', 'Admin Campus', UserRole.admin, true, StudentCard.none, const <String>[]),
      (amelId, 'amel@esprit.tn', 'Amel Ben Salah', UserRole.student, false, pendingCard, skills),
      (sarraId, 'sarra@esprit.tn', 'Sarra Trabelsi', UserRole.student, false, pendingCard, skills),
      (youssefId, 'youssef@esprit.tn', 'Youssef Gharbi', UserRole.student, false, pendingCard, skills),
      (
        recruiterId,
        'recruteur@vermeg.tn',
        'Recruteur Vermeg',
        UserRole.recruiter,
        false,
        StudentCard.none,
        const <String>[]
      ),
      // Profil complété par _jawherProfile (carte vérifiée).
      (jawherId, 'jawher@esprit.tn', 'Jawher Khalifa', UserRole.student, false, pendingCard, skills),
    ];
    for (final (uid, email, name, role, verified, card, userSkills) in accounts) {
      // Même forme que AuthService.registerWithEmail.
      _set(AuthService.accountsCollection, uid, {'email': email, 'password': hash, 'createdAt': _now});
      _set(
        AppConstants.usersCollection,
        uid,
        AppUser(
          id: uid,
          fullName: name,
          email: email,
          role: role,
          isVerifiedStudent: verified,
          createdAt: _now,
          skills: userSkills,
          studentCard: card,
        ).toMap(),
      );
    }
  }

  /// Profil de Jawher (écran Profil de la maquette).
  void _jawherProfile() {
    _set(
      AppConstants.usersCollection,
      jawherId,
      AppUser(
        id: jawherId,
        fullName: 'Jawher Khalifa',
        email: 'jawher@esprit.tn',
        major: 'Génie Informatique',
        year: '4SIM2',
        createdAt: DateTime.utc(2024, 9, 16, 8),
        skills: const ['Flutter', 'Firebase', 'Dart', 'UI/UX', 'Git'],
        isVerifiedStudent: true,
        studentCard: StudentCard(
          status: StudentCardStatus.verified,
          imagePath: cardImage,
          submittedAt: DateTime.utc(2026, 10, 9, 10),
          reviewedBy: adminId,
          reviewedAt: DateTime.utc(2026, 10, 12, 14),
        ),
      ).toMap(),
    );
  }

  // --- Événements --------------------------------------------------------------

  void _events() {
    var hackathon = DateTime.utc(2026, 11, 8, 9);
    if (!hackathon.isAfter(_now)) {
      // Lancé après la date : samedi suivant.
      hackathon = _ahead(7 + (DateTime.saturday - _now.weekday) % 7);
    }
    final attendees = [for (final (uid, _) in _students) uid];
    final events = [
      (
        'hackathon',
        'Hackathon ESPRIT 2026',
        'Associatif',
        hackathon,
        'Bloc E, amphi 3',
        _photo('team'),
        '24 heures pour prototyper une app utile au campus, en équipes de 4. '
            'Mentors, repas et prix pour les trois meilleurs projets.',
        86
      ),
      (
        'foot',
        'Tournoi de foot inter-classes',
        'Sport',
        hackathon.add(const Duration(days: 6)),
        'Terrain ESPRIT Ghazela',
        null,
        'Phase de poules le matin, finales l\'après-midi. Inscription par équipe de 7.',
        54
      ),
      (
        'jobfair',
        'ESPRIT Job Fair',
        'Job Fair',
        hackathon.add(const Duration(days: 11)),
        'Hall du Bloc A',
        _photo('campus'),
        'Plus de 40 entreprises recrutent stagiaires et jeunes diplômés. Apporte ton CV imprimé.',
        212
      ),
      (
        'ia',
        'Conférence : IA générative en entreprise',
        'Conférence',
        hackathon.add(const Duration(days: 18)),
        'Bloc E, amphi 1',
        _photo('whiteboard'),
        'Retours d\'expérience d\'ingénieurs ESPRIT alumni.',
        97
      ),
      (
        'culture',
        'Soirée culturelle des clubs',
        'Culture',
        hackathon.add(const Duration(days: 27)),
        'Auditorium',
        null,
        'Musique, théâtre et stands des clubs étudiants.',
        140
      ),
    ];
    for (final (key, title, category, start, place, poster, description, count) in events) {
      final created = _ago(days: 20);
      _set(
        AppConstants.eventsCollection,
        'demo-$key',
        EventModel(
          id: 'demo-$key',
          organizerId: adminId,
          organizerName: key == 'hackathon' ? 'Club Info ESPRIT' : 'Vie étudiante',
          title: title,
          description: description,
          category: category,
          startDate: start,
          location: place,
          latitude: 36.8992,
          longitude: 10.1897,
          registeredUserIds: [
            ...attendees,
            for (var n = 1; n < count; n++) _fakeId(n),
          ],
          posterUrl: poster,
          createdAt: created,
          updatedAt: created,
        ).toMap(),
      );
    }
  }

  // --- Annonces ----------------------------------------------------------------

  void _annonces() {
    final annonces = [
      (
        'officielle-examens',
        adminId,
        'Administration ESPRIT',
        'Calendrier des examens du semestre 1',
        'Le calendrier est en ligne. Les examens commencent le 5 janvier ; '
            'vérifiez votre salle sur l\'espace étudiant.',
        'Officielle',
        true,
        true,
        1
      ),
      (
        'officielle-cartes',
        adminId,
        'Administration ESPRIT',
        'Vérification des cartes étudiantes',
        'Déposez une photo de votre carte depuis votre profil pour obtenir le badge « Étudiant vérifié ».',
        'Officielle',
        true,
        false,
        3
      ),
    ];
    const jawherPosts = [
      ('Perdu & Trouvé', 'Clé USB noire trouvée en salle E204', 'Gravée « RS ». Je la dépose à l\'accueil du Bloc E.'),
      ('Générale', 'Groupe de révision Flutter', 'On se retrouve chaque mardi 17 h en salle E101. Tous niveaux.'),
      ('Générale', 'Covoiturage Ariana → Ghazela', 'Départ 7 h 30 du lundi au jeudi, 2 places libres.'),
      ('Perdu & Trouvé', 'Carte étudiante perdue', 'Au nom de Mehdi B., probablement près de la cafétéria.'),
      ('Générale', 'Atelier Git pour les 3A', 'Initiation aux branches et pull requests, jeudi 14 h.'),
      ('Générale', 'Recherche binôme PFE mobile', 'Projet Flutter + Firebase, sujet déjà validé.'),
      ('Perdu & Trouvé', 'Écouteurs blancs trouvés', 'Oubliés à la bibliothèque, table 12.'),
      ('Générale', 'Tournoi e-sport du club Info', 'Inscriptions ouvertes jusqu\'à vendredi.'),
      ('Générale', 'Partage de notes Réseaux', 'Mes notes de cours de 4SIM2 sont dispo, demande en message.'),
      ('Perdu & Trouvé', 'Parapluie bleu trouvé', 'Laissé dans l\'amphi 3 après le cours de 10 h.'),
      ('Générale', 'Club photo : sortie à Sidi Bou Saïd', 'Samedi matin, rendez-vous devant le Bloc A.'),
      ('Générale', 'Bénévoles pour le Hackathon', 'Le club Info cherche 10 bénévoles pour l\'accueil.'),
    ];
    for (final (i, (category, title, body)) in jawherPosts.indexed) {
      annonces.add((
        'jawher-${(i + 1).toString().padLeft(2, '0')}',
        jawherId,
        'Jawher Khalifa',
        title,
        body,
        category,
        false,
        false,
        2 + i * 3,
      ));
    }
    for (final (key, author, name, title, body, category, pinned, urgent, days) in annonces) {
      _set(
        AppConstants.annoncesCollection,
        'demo-$key',
        AnnonceModel(
          id: 'demo-$key',
          authorId: author,
          authorName: name,
          title: title,
          content: body,
          category: category,
          isPinned: pinned,
          isUrgent: urgent,
          createdAt: _ago(days: days),
          commentCount: _rng.nextInt(15),
        ).toMap(),
      );
    }
  }

  // --- Stage & Emploi ----------------------------------------------------------

  void _jobs() {
    const offers = [
      (
        'vermeg-pfe',
        'Vermeg',
        'Stage PFE : application mobile Flutter',
        JobType.stage,
        'Tunis, Lac 2',
        ['Flutter', 'Firebase', 'Dart'],
        4
      ),
      (
        'vermeg-ete',
        'Vermeg',
        'Stage d\'été : back-office Firebase',
        JobType.stage,
        'Tunis, Lac 2',
        ['Firebase', 'Node.js'],
        9
      ),
      (
        'talan-mobile',
        'Talan Tunisie',
        'Développeur mobile junior',
        JobType.emploi,
        'Tunis, Centre Urbain Nord',
        ['Flutter', 'Git', 'REST'],
        6
      ),
      (
        'instadeep-ia',
        'InstaDeep',
        'Stage PFE : IA et vision par ordinateur',
        JobType.stage,
        'Tunis',
        ['Python', 'PyTorch'],
        12
      ),
      ('sofrecom-uiux', 'Sofrecom', 'Stage UI/UX design mobile', JobType.stage, 'Tunis, Lac 1', ['UI/UX', 'Figma'], 2),
      (
        'proxym-fullstack',
        'Proxym Group',
        'Ingénieur full-stack',
        JobType.emploi,
        'Sousse',
        ['Angular', 'Spring Boot', 'Git'],
        15
      ),
    ];
    final byKey = {for (final o in offers) o.$1: o};
    for (final (key, company, title, type, place, skills, days) in offers) {
      _set(
        AppConstants.jobOffersCollection,
        'demo-$key',
        JobOfferModel(
          id: 'demo-$key',
          recruiterId: recruiterId,
          companyName: company,
          title: title,
          description: '$company recherche un profil motivé pour rejoindre son équipe produit.',
          type: type,
          location: place,
          requiredSkills: skills,
          postedAt: _ago(days: days),
          deadline: _ahead(30 + days),
        ).toMap(),
      );
    }
    const applied = [
      ('vermeg-pfe', ApplicationStatus.seen, 3),
      ('talan-mobile', ApplicationStatus.sent, 1),
      ('sofrecom-uiux', ApplicationStatus.accepted, 8),
    ];
    for (final (key, status, days) in applied) {
      final offer = byKey[key]!;
      _set(
        AppConstants.applicationsCollection,
        'demo-jawher-$key',
        ApplicationModel(
          id: 'demo-jawher-$key',
          jobOfferId: 'demo-$key',
          jobTitle: offer.$3,
          companyName: offer.$2,
          candidateId: jawherId,
          coverLetter: 'Étudiant en 4SIM2, je développe en Flutter et Firebase depuis deux ans.',
          status: status,
          appliedAt: _ago(days: days),
        ).toMap(),
      );
    }
  }

  // --- Comptes fictifs (écran Analytics) ---------------------------------------

  static String _fakeId(int n) => 'demo-user-${n.toString().padLeft(4, '0')}';

  static const _first = [
    'Aymen', 'Mariem', 'Skander', 'Nour', 'Rania', 'Mohamed', 'Yasmine', 'Firas', 'Ines', 'Oussama', //
    'Eya', 'Hamza', 'Sirine', 'Wassim', 'Chaima', 'Khalil', 'Malek', 'Asma', 'Bilel', 'Rim', //
    'Ahmed', 'Salma', 'Anis', 'Hiba', 'Ghassen', 'Emna', 'Mehdi', 'Fatma', 'Seif', 'Amira',
  ];
  static const _last = [
    'Ben Ali', 'Trabelsi', 'Jebali', 'Mansouri', 'Hammami', 'Bouazizi', 'Gharbi', 'Chaabane', //
    'Karray', 'Dridi', 'Ayari', 'Sassi', 'Mejri', 'Baccouche', 'Ferchichi', 'Zouari', 'Khemiri', //
    'Jlassi', 'Ouertani', 'Rekik',
  ];
  static const _majors = ['Génie Informatique', 'Génie Civil', 'Génie Électromécanique', 'Génie Télécom', 'Business'];
  static const _years = ['1ère année', '2ème année', '3ème année', '4ème année', '5ème année'];
  static const _companies = ['vermeg.tn', 'talan.tn', 'sofrecom.tn', 'instadeep.com', 'proxym.tn', 'telnet.tn'];

  T _pick<T>(List<T> list) => list[_rng.nextInt(list.length)];

  double _uniform(double a, double b) => a + _rng.nextDouble() * (b - a);

  /// [total] inscriptions réparties sur [days] jours, courbe croissante
  /// selon [rising], avec un pic au jour 22 (le « +84 » de la maquette).
  List<int> _curve(int total, int days, double rising) {
    final weights = [for (var i = 0; i < days; i++) (1 + i / days * rising) * _uniform(0.85, 1.15)];
    weights[21] *= 1.9;
    final sum = weights.reduce((a, b) => a + b);
    final counts = [for (final w in weights) (w / sum * total).floor()];
    final missing = total - counts.reduce((a, b) => a + b);
    for (var i = 0; i < missing; i++) {
      counts[days - 1 - i % days]++;
    }
    return counts;
  }

  /// 30 derniers jours : 1 248 inscrits avec les 5 comptes réels du jour
  /// (Jawher date de 2024). 30 jours précédents : 1 114, soit +12 %.
  void _fakeAccounts() {
    final dates = <DateTime>[];
    for (final (offset, total, rising) in const [(0, 1243, 1.4), (30, 1114, 0.6)]) {
      final counts = _curve(total, 30, rising);
      for (var i = 0; i < counts.length; i++) {
        final day = _now.subtract(Duration(days: offset + 29 - i));
        for (var k = 0; k < counts[i]; k++) {
          final at = DateTime.utc(day.year, day.month, day.day, 7 + _rng.nextInt(16), _rng.nextInt(60));
          dates.add(at.isAfter(_now) ? _now : at);
        }
      }
    }
    dates.sort();

    // Rôles sur l'ensemble des comptes (6 réels inclus) : 77 / 17 / 6 %.
    final total = dates.length + 6;
    final roles = [
      for (var i = 0; i < (total * 0.06).round() - 1; i++) UserRole.admin,
      for (var i = 0; i < (total * 0.17).round() - 1; i++) UserRole.recruiter,
    ];
    roles.addAll(List.filled(dates.length - roles.length, UserRole.student));
    roles.shuffle(_rng);

    final students = [
      for (var i = 0; i < roles.length; i++)
        if (roles[i] == UserRole.student) i
    ];
    List<int> sample(List<int> from, int n) => (from.toList()..shuffle(_rng)).take(n).toList();
    final pending = sample(students, 34).toSet(); // + Amel, Sarra, Youssef = 37
    final verified = sample([
      for (final i in students)
        if (!pending.contains(i)) i
    ], students.length ~/ 2)
        .toSet();
    final rejected = sample(
      [
        for (final i in students)
          if (!pending.contains(i) && !verified.contains(i)) i
      ],
      40,
    ).toSet();

    for (var i = 0; i < dates.length; i++) {
      final uid = _fakeId(i + 1);
      final created = dates[i];
      final role = roles[i];
      final first = _pick(_first);
      final last = _pick(_last);
      final domain = role == UserRole.recruiter ? _pick(_companies) : 'esprit.tn';
      var card = StudentCard.none;
      if (pending.contains(i) || verified.contains(i) || rejected.contains(i)) {
        final reviewed = !pending.contains(i);
        card = StudentCard(
          status: pending.contains(i)
              ? StudentCardStatus.pending
              : verified.contains(i)
                  ? StudentCardStatus.verified
                  : StudentCardStatus.rejected,
          imagePath: cardImage,
          submittedAt: created.add(const Duration(hours: 2)),
          reviewedBy: reviewed ? adminId : null,
          reviewedAt: reviewed ? created.add(const Duration(days: 1)) : null,
          rejectReason: rejected.contains(i) ? 'Photo floue, carte illisible.' : null,
        );
      }
      final isStudent = role == UserRole.student;
      _set(
        AppConstants.usersCollection,
        uid,
        AppUser(
          id: uid,
          fullName: '$first $last',
          email: '$first.${last.replaceAll(' ', '')}${i + 1}@$domain'.toLowerCase(),
          role: role,
          major: isStudent ? _pick(_majors) : null,
          year: isStudent ? _pick(_years) : null,
          isVerifiedStudent: verified.contains(i),
          createdAt: created,
          studentCard: card,
        ).toMap(),
      );
    }
  }
}
