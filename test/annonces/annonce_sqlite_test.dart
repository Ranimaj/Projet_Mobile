import 'dart:io';

import 'package:campusconnect/models/annonce_model.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/services/sqlite/annonce_database.dart';
import 'package:campusconnect/services/sqlite/annonce_store.dart';
import 'package:campusconnect/services/sqlite/local_annonce_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

AnnonceModel _annonce({
  String id = 'x',
  String title = 'Titre',
  String category = 'Générale',
  bool pinned = false,
  bool urgent = false,
  DateTime? createdAt,
  List<String> majors = const [],
  List<String> years = const [],
  double? lat,
  double? lng,
  String? place,
}) =>
    AnnonceModel(
      id: id,
      authorId: 'u1',
      authorName: 'Alice',
      title: title,
      content: 'Contenu',
      category: category,
      isPinned: pinned,
      isUrgent: urgent,
      createdAt: createdAt ?? DateTime(2026, 10, 1),
      targetMajors: majors,
      targetYears: years,
      latitude: lat,
      longitude: lng,
      locationName: place,
    );

void main() {
  setUpAll(sqfliteFfiInit);

  group('AnnonceDatabase / LocalAnnonceRepository', () {
    late Directory dir;
    late LocalAnnonceRepository repo;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('annonces_sqlite');
      repo = LocalAnnonceRepository(
        openDatabase: () =>
            AnnonceDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/annonces.db'),
      );
    });

    tearDown(() async {
      await (await repo.database).close();
      dir.deleteSync(recursive: true);
    });

    test('une ligne garde tous les champs de l\'annonce', () {
      final a = _annonce(
        id: 'a1',
        urgent: true,
        majors: const ['Génie Informatique'],
        years: const ['3ème année'],
        lat: 36.9,
        lng: 10.2,
        place: 'Bloc B',
        createdAt: DateTime(2026, 11, 8, 10, 30),
      );
      final back = AnnonceDatabase.fromRow(AnnonceDatabase.toRow(a));
      expect(back.id, 'a1');
      expect(back.isUrgent, isTrue);
      expect(back.targetMajors, ['Génie Informatique']);
      expect(back.targetYears, ['3ème année']);
      expect(back.locationName, 'Bloc B');
      expect(back.latitude, 36.9);
      expect(back.createdAt, DateTime(2026, 11, 8, 10, 30));
      expect(back.updatedAt, isNull);
    });

    test('création, lecture : épinglées d\'abord puis plus récentes', () async {
      await repo.create(_annonce(title: 'ancienne', createdAt: DateTime(2026, 1, 1)));
      await repo.create(_annonce(title: 'récente', createdAt: DateTime(2026, 3, 1)));
      await repo.create(_annonce(title: 'épinglée', pinned: true, createdAt: DateTime(2025, 1, 1)));

      final titles = [for (final a in await repo.fetchAll()) a.title];
      expect(titles, ['épinglée', 'récente', 'ancienne']);
    });

    test('create génère un id ; explicitId est respecté', () async {
      final generated = await repo.create(_annonce());
      expect(generated, isNotEmpty);
      expect((await repo.byId(generated))!.title, 'Titre');

      await repo.create(_annonce(title: 'fixe'), explicitId: 'mon-id');
      expect((await repo.byId('mon-id'))!.title, 'fixe');
    });

    test('update remplace la ligne, delete la supprime', () async {
      final id = await repo.create(_annonce(title: 'avant'));
      final current = (await repo.byId(id))!;
      await repo.update(current.copyWith(title: 'après', isPinned: true));

      final updated = (await repo.byId(id))!;
      expect(updated.title, 'après');
      expect(updated.isPinned, isTrue);
      expect(await repo.fetchAll(), hasLength(1));

      await repo.delete(id);
      expect(await repo.byId(id), isNull);
    });

    test('un lieu sans coordonnées n\'est pas enregistré', () async {
      final id = await repo.create(_annonce(place: 'Bloc B'));
      final back = (await repo.byId(id))!;
      expect(back.locationName, isNull);
      expect(back.hasLocation, isFalse);
    });

    test('les données survivent à la réouverture du fichier', () async {
      final id = await repo.create(_annonce(title: 'durable'));
      await (await repo.database).close();

      final reopened = LocalAnnonceRepository(
        openDatabase: () =>
            AnnonceDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/annonces.db'),
      );
      expect((await reopened.byId(id))!.title, 'durable');
      await (await reopened.database).close();
      // tearDown referme `repo` : la fermeture d'une base déjà fermée est sans effet.
    });
  });

  group('AnnonceProvider (dépôt en mémoire)', () {
    test('création, épinglage automatique, modification, épinglage, suppression', () async {
      final provider = AnnonceProvider(repository: _MemoryStore());

      final id = await provider.createAnnonce(_annonce(category: 'Officielle'));
      expect(provider.byId(id)!.isPinned, isTrue);

      await provider.updateAnnonce(
        provider.byId(id)!,
        title: 'Modifiée',
        content: 'Nouveau',
        category: 'Générale',
        isUrgent: true,
        targetMajors: const ['Business'],
        targetYears: const [],
      );
      final edited = provider.byId(id)!;
      expect(edited.title, 'Modifiée');
      expect(edited.isPinned, isFalse, reason: 'plus officielle : désépinglée');
      expect(edited.isUrgent, isTrue);
      expect(edited.targetMajors, ['Business']);
      expect(edited.updatedAt, isNotNull);

      await provider.pinAnnonce(id, true);
      expect(provider.byId(id)!.isPinned, isTrue);

      await provider.deleteAnnonce(id);
      expect(provider.byId(id), isNull);
      expect(provider.items, isEmpty);
    });

    test('items : filtre par catégorie, épinglées d\'abord', () async {
      final store = _MemoryStore();
      await store.create(_annonce(title: 'a', category: 'Générale', createdAt: DateTime(2026, 1, 1)));
      await store.create(_annonce(title: 'b', category: 'Perdu & Trouvé', createdAt: DateTime(2026, 2, 1)));
      await store.create(_annonce(title: 'c', category: 'Générale', pinned: true, createdAt: DateTime(2025, 1, 1)));
      final provider = AnnonceProvider(repository: store);
      await provider.load();

      expect([for (final a in provider.items) a.title], ['c', 'b', 'a']);
      provider.setCategoryFilter('Générale');
      expect([for (final a in provider.items) a.title], ['c', 'a']);
    });
  });
}

class _MemoryStore implements AnnonceStore {
  final Map<String, AnnonceModel> _rows = {};
  int _n = 0;

  @override
  Future<List<AnnonceModel>> fetchAll() async => _rows.values.toList();

  @override
  Future<AnnonceModel?> byId(String id) async => _rows[id];

  @override
  Future<String> create(AnnonceModel item, {String? explicitId}) async {
    final id = explicitId ?? 'id${_n++}';
    _rows[id] = AnnonceModel(
      id: id,
      authorId: item.authorId,
      authorName: item.authorName,
      title: item.title,
      content: item.content,
      category: item.category,
      isPinned: item.isPinned,
      isUrgent: item.isUrgent,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      targetMajors: item.targetMajors,
      targetYears: item.targetYears,
      locationName: item.locationName,
      latitude: item.latitude,
      longitude: item.longitude,
    );
    return id;
  }

  @override
  Future<void> update(AnnonceModel item) async => _rows[item.id] = item;

  @override
  Future<void> delete(String id) async => _rows.remove(id);
}
