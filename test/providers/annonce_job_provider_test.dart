import 'dart:io';

import 'package:campusconnect/models/annonce_model.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/local_db.dart';

void main() {
  late LocalStore store;

  setUpAll(() => registerFallbackValue(File('x')));
  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
  });
  tearDown(closeTestDatabase);

  AnnonceModel draft(String category, DateTime at) => AnnonceModel(
        id: '',
        authorId: 'adm',
        authorName: 'Scolarité',
        title: category,
        content: '...',
        category: category,
        createdAt: at,
      );

  test('an "Officielle" annonce is pinned and listed first', () async {
    final provider = AnnonceProvider(store: store);
    await provider.createAnnonce(draft('Générale', DateTime(2026, 11, 9)));
    final id = await provider.createAnnonce(draft('Officielle', DateTime(2026, 11, 1)));

    expect(provider.items.first.id, id);
    expect(provider.items.first.isPinned, isTrue);
    expect(store.get('annonces', id)!['isPinned'], isTrue);

    await provider.pinAnnonce(id, false);
    expect(provider.items.first.category, 'Générale');
    await provider.deleteAnnonce(id);
    expect(provider.items, hasLength(1));
  });
}
