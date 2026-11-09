import 'package:campusconnect/services/local_repository.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/local_db.dart';

void main() {
  late LocalStore store;

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
  });
  tearDown(closeTestDatabase);

  group('documents', () {
    test('set, get, exists, delete', () async {
      await store.set('users', 'u1', {'fullName': 'Amel', 'createdAt': DateTime.utc(2026, 1, 2)});
      expect(store.exists('users', 'u1'), isTrue);
      expect(store.get('users', 'u1')!['fullName'], 'Amel');
      expect(store.get('users', 'u1')!['createdAt'], DateTime.utc(2026, 1, 2));
      await store.delete('users', 'u1');
      expect(store.get('users', 'u1'), isNull);
    });

    test('merge crée ou complète ; null efface le champ', () async {
      await store.merge('users', 'u1', {'a': 1, 'b': 2});
      await store.merge('users', 'u1', {'b': null, 'c': 3});
      expect(store.get('users', 'u1'), {'a': 1, 'c': 3});
    });

    test('setAll écrit plusieurs documents, une seule notification, persistés', () async {
      var notified = 0;
      final sub = store.watch('users').skip(1).listen((_) => notified++);
      await pumpEventQueue();
      await store.set('users', 'u0', {'n': 0});
      await store.setAll('users', {
        'u0': {'n': 10},
        'u1': {'n': 1},
        'u2': {'n': 2},
      });
      await pumpEventQueue();
      await sub.cancel();
      expect(notified, 2);
      expect({for (final d in store.all('users')) d.id: d.data['n']}, {'u0': 10, 'u1': 1, 'u2': 2});
    });

    test('update exige un document existant', () async {
      expect(() => store.update('users', 'absent', {'a': 1}), throwsA(isA<DocumentNotFound>()));
      await store.set('users', 'u1', {'a': 1});
      await store.update('users', 'u1', {'b': 2});
      expect(store.get('users', 'u1'), {'a': 1, 'b': 2});
    });

    test('where, firstWhere et deleteWhere', () async {
      await store.set('logins', 'l1', {'uid': 'a'});
      await store.set('logins', 'l2', {'uid': 'b'});
      await store.set('logins', 'l3', {'uid': 'a'});
      expect(store.where('logins', (d) => d['uid'] == 'a').map((d) => d.id).toSet(), {'l1', 'l3'});
      expect(store.firstWhere('logins', (d) => d['uid'] == 'b')!.id, 'l2');
      expect(store.firstWhere('logins', (d) => d['uid'] == 'z'), isNull);
      expect(await store.deleteWhere('logins', (d) => d['uid'] == 'a'), 2);
      expect(store.all('logins').map((d) => d.id), ['l2']);
    });

    test('lire puis écrire sans await est atomique (remplace une transaction)', () async {
      await store.set('events', 'e1', {'seats': 0});
      // 20 inscriptions lancées « en même temps » : aucune n'est perdue.
      await Future.wait([
        for (var i = 0; i < 20; i++)
          store.update('events', 'e1', {'seats': (store.get('events', 'e1')!['seats'] as int) + 1}),
      ]);
      expect(store.get('events', 'e1')!['seats'], 20);
    });
  });

  group('temps réel', () {
    test('watch émet la collection tout de suite puis à chaque changement', () async {
      final seen = <List<String>>[];
      final sub = store.watch('annonces').listen((docs) => seen.add([for (final d in docs) d.id]..sort()));
      await pumpEventQueue();
      await store.set('annonces', 'a1', {});
      await store.set('annonces', 'a2', {});
      await store.set('events', 'e1', {}); // autre collection : rien
      await store.delete('annonces', 'a1');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [
        <String>[],
        ['a1'],
        ['a1', 'a2'],
        ['a2'],
      ]);
    });

    test('watchDoc suit un document, null quand il disparaît', () async {
      final seen = <Object?>[];
      final sub = store.watchDoc('users', 'u1').listen((d) => seen.add(d?['n']));
      await pumpEventQueue();
      await store.set('users', 'u1', {'n': 1});
      await store.merge('users', 'u1', {'n': 2});
      await store.delete('users', 'u1');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [null, 1, 2, null]);
    });
  });

  test('réglages : getValue / setValue', () async {
    await store.setValue('auth.session_uid', 'u1');
    expect(store.getValue('auth.session_uid'), 'u1');
    await store.setValue('auth.session_uid', null);
    expect(store.getValue('auth.session_uid'), isNull);
  });

  test('parseDate : DateTime, ISO, millisecondes, sinon null', () {
    final d = DateTime.utc(2026, 3, 4, 5, 6);
    expect(parseDate(d), d.toLocal());
    expect(parseDate('2026-03-04T05:06:00Z'), d.toLocal());
    expect(parseDate(d.millisecondsSinceEpoch), d.toLocal());
    expect(parseDate(null), isNull);
    expect(parseDate('pas une date'), isNull);
  });

  test('LocalRepository : create, fetch, update, delete, watchAll', () async {
    final repo = LocalRepository<String>(
      collectionName: 'annonces',
      fromMap: (id, m) => '$id:${m['title']}',
      toMap: (title) => {'title': title},
    );
    final id = await repo.create('Examens');
    await repo.create('Bourses', explicitId: 'b1');
    expect(repo.fetch(id), '$id:Examens');
    expect(repo.fetchAll(), hasLength(2));
    await repo.update('b1', {'title': 'Bourses 2026'});
    expect(repo.fetch('b1'), 'b1:Bourses 2026');
    final first = await repo.watchAll().first;
    expect(first, hasLength(2));
    await repo.delete(id);
    expect(repo.fetchAll(), ['b1:Bourses 2026']);
  });
}
