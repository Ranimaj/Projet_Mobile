import 'package:campusconnect/core/constants/app_constants.dart';
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
      expect(AppConstants.campusMajors, contains('Génie Informatique'));
      expect(AppConstants.campusMajors, isNot(contains('Autre')));
    });

    test('campusYears reprend les années du profil, sans « Alumni »', () {
      expect(AppConstants.campusYears, contains('3ème année'));
      expect(AppConstants.campusYears, isNot(contains('Alumni')));
    });
  });

  group('SegmentTopics', () {
    test('slug retire accents et caractères spéciaux', () {
      expect(SegmentTopics.slug('Génie Électromécanique'), 'genie-electromecanique');
      expect(SegmentTopics.slug('  Génie Télécom  '), 'genie-telecom');
    });

    test('majorTopic : chaque filière du profil a un topic FCM valide', () {
      final valid = RegExp(r'^major_[a-z0-9-]+$');
      for (final m in AppConstants.campusMajors) {
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
    test('toMap / fromMap conservent les données et le ciblage', () {
      final a = _annonce(
          category: 'Officielle', majors: ['Génie Informatique'], years: ['3ème année']);
      final map = a.toMap();
      expect(map['majorTopics'], ['major_genie-informatique']);
      expect(map['yearTopics'], ['year_3']);

      final back = AnnonceModel.fromMap('a1', map);
      expect(back.title, 'Titre');
      expect(back.targetMajors, ['Génie Informatique']);
      expect(back.targetYears, ['3ème année']);
      expect(back.isOfficial, isTrue);
    });

    test('fromMap relit aussi une date ISO (cache local)', () {
      final back = AnnonceModel.fromMap('a1', {
        ..._annonce().toMap(),
        'createdAt': '2026-10-01T09:30:00.000',
      });
      expect(back.createdAt, DateTime(2026, 10, 1, 9, 30));
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
