import 'package:campusconnect/core/constants/annonce_constants.dart';
import 'package:campusconnect/core/utils/segment_topics.dart';
import 'package:campusconnect/models/annonce_model.dart';
import 'package:flutter_test/flutter_test.dart';

AnnonceModel _annonce({
  String category = 'Générale',
  List<String> majors = const [],
  List<String> years = const [],
}) =>
    AnnonceModel(
      id: 'a1',
      authorId: 'u1',
      authorName: 'Alice',
      title: 'Titre',
      content: 'Contenu de test',
      category: category,
      createdAt: DateTime(2026, 10, 1, 9, 30),
      targetMajors: majors,
      targetYears: years,
    );

void main() {
  group('Ciblage : filières / années du profil', () {
    test('campusMajors reprend les filières du profil, sans « Autre »', () {
      expect(AnnonceConstants.majors, contains('Génie Informatique'));
      expect(AnnonceConstants.majors, isNot(contains('Autre')));
    });

    test('campusYears reprend les années du profil, sans « Alumni »', () {
      expect(AnnonceConstants.years, contains('3ème année'));
      expect(AnnonceConstants.years, isNot(contains('Alumni')));
    });
  });

  group('SegmentTopics', () {
    test('slug retire accents et caractères spéciaux', () {
      expect(SegmentTopics.slug('Génie Électromécanique'), 'genie-electromecanique');
      expect(SegmentTopics.slug('  Génie Télécom  '), 'genie-telecom');
    });

    test('majorTopic : chaque filière du profil a un topic FCM valide', () {
      final valid = RegExp(r'^major_[a-z0-9-]+$');
      for (final m in AnnonceConstants.majors) {
        expect(SegmentTopics.majorTopic(m), matches(valid), reason: m);
      }
      expect(SegmentTopics.majorTopic('Génie Informatique'), 'major_genie-informatique');
      expect(SegmentTopics.majorTopic(''), isNull);
      expect(SegmentTopics.majorTopic(null), isNull);
    });

    test('yearTopic utilise le premier chiffre', () {
      expect(SegmentTopics.yearTopic('3ème année'), 'year_3');
      expect(SegmentTopics.yearTopic('3A'), 'year_3');
      expect(SegmentTopics.yearTopic(null), isNull);
    });

    test('forUser contient toujours all_campus', () {
      expect(SegmentTopics.forUser(null, null), {'all_campus'});
      expect(SegmentTopics.forUser('Génie Informatique', '2ème année'),
          {'all_campus', 'major_genie-informatique', 'year_2'});
    });
  });

  group('AnnonceModel', () {
    test('edited efface le lieu et ne change l\'épinglage que si demandé', () {
      final original = AnnonceModel(
        id: 'a1',
        authorId: 'u1',
        authorName: 'Alice',
        title: 'Avant',
        content: 'c',
        category: 'Officielle',
        isPinned: true,
        createdAt: DateTime(2026, 10, 1),
        locationName: 'Bloc B',
        latitude: 36.9,
        longitude: 10.2,
      );
      final edited = original.edited(
        title: 'Après',
        content: 'c2',
        category: 'Générale',
        isUrgent: true,
        targetMajors: const ['Business'],
        targetYears: const [],
        updatedAt: DateTime(2026, 10, 2),
      );
      expect(edited.id, 'a1');
      expect(edited.title, 'Après');
      expect(edited.hasLocation, isFalse);
      expect(edited.isPinned, isTrue);
      expect(edited.createdAt, original.createdAt);
      expect(edited.updatedAt, DateTime(2026, 10, 2));
      expect(
        original
            .edited(
              title: 't',
              content: 'c',
              category: 'Générale',
              isUrgent: false,
              targetMajors: const [],
              targetYears: const [],
              updatedAt: DateTime(2026, 10, 2),
              isPinned: false,
            )
            .isPinned,
        isFalse,
      );
    });

    test('matchesUser : listes vides = tout le campus, sinon filière ET année', () {
      expect(_annonce().matchesUser(major: 'Génie Civil', year: '1ère année'), isTrue);

      final targeted =
          _annonce(majors: ['Génie Informatique'], years: ['3ème année']);
      expect(targeted.matchesUser(major: 'Génie Informatique', year: '3ème année'), isTrue);
      expect(targeted.matchesUser(major: 'Génie Informatique', year: '2ème année'), isFalse);
      expect(targeted.matchesUser(major: 'Génie Civil', year: '3ème année'), isFalse);
      expect(targeted.matchesUser(major: null, year: null), isFalse);
    });

    test('matchesQuery cherche dans titre, contenu, auteur et catégorie', () {
      final a = _annonce();
      expect(a.matchesQuery('titre'), isTrue);
      expect(a.matchesQuery('TEST'), isTrue);
      expect(a.matchesQuery('alice'), isTrue);
      expect(a.matchesQuery('introuvable'), isFalse);
      expect(a.matchesQuery('  '), isTrue);
    });
  });
}