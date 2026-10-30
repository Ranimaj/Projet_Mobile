import 'package:campusconnect/core/utils/annonce_filter.dart';
import 'package:campusconnect/models/annonce_model.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

AnnonceModel _a(
  String id, {
  String authorId = 'other',
  String title = 'Annonce',
  bool urgent = false,
  List<String> majors = const [],
  List<String> years = const [],
}) =>
    AnnonceModel(
      id: id,
      authorId: authorId,
      authorName: 'Auteur',
      title: title,
      content: 'Contenu',
      category: 'Générale',
      isUrgent: urgent,
      createdAt: DateTime(2026, 10, 1),
      targetMajors: majors,
      targetYears: years,
    );

final _me = AppUser(
  id: 'me',
  fullName: 'Moi',
  email: 'moi@esprit.tn',
  major: 'Génie Informatique',
  year: '3ème année',
  createdAt: DateTime(2026, 9, 1),
);

void main() {
  final all = [
    _a('1', title: 'Examens', urgent: true),
    _a('2', authorId: 'me', title: 'Mon objet perdu'),
    _a('3', majors: ['Génie Civil']),
    _a('4', majors: ['Génie Informatique'], years: ['3ème année']),
  ];
  ids(List<AnnonceModel> l) => l.map((a) => a.id).toList();

  test('sans critère : tout est conservé, dans l\'ordre', () {
    const f = AnnonceFilter();
    expect(f.activeCount, 0);
    expect(ids(f.apply(all, user: _me)), ['1', '2', '3', '4']);
  });

  test('recherche texte', () {
    expect(ids(const AnnonceFilter(query: 'objet').apply(all)), ['2']);
  });

  test('urgentes', () {
    expect(ids(const AnnonceFilter(onlyUrgent: true).apply(all)), ['1']);
  });

  test('mes annonces', () {
    expect(ids(const AnnonceFilter(onlyMine: true).apply(all, user: _me)), ['2']);
    expect(const AnnonceFilter(onlyMine: true).apply(all), isEmpty);
  });

  test('pour moi : sans ciblage ou ciblant ma filière et mon année', () {
    expect(ids(const AnnonceFilter(onlyForMe: true).apply(all, user: _me)), ['1', '2', '4']);
  });

  test('activeCount compte les critères actifs', () {
    const f = AnnonceFilter(query: 'x', onlyUrgent: true, onlyForMe: true);
    expect(f.activeCount, 3);
    expect(f.copyWith(onlyUrgent: false).activeCount, 2);
  });
}
