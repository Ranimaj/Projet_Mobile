import 'dart:io';

import 'package:campusconnect/models/annonce_model.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/providers/job_provider.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/local_db.dart';
import '../helpers/mocks.dart';

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

  test('applying copies the CV into the app folder and tracks the status', () async {
    final storage = MockStorageService();
    when(() => storage.saveDocument(any(), folder: 'cv')).thenAnswer((_) async => '/app/cv/1.pdf');
    final provider = JobProvider(store: store, storage: storage);
    final offerId = await provider.createOffer(JobOfferModel(
      id: '',
      recruiterId: 'r',
      companyName: 'Vermeg',
      title: 'Stage Flutter',
      description: '',
      type: JobType.stage,
      location: 'Tunis',
      postedAt: DateTime(2026, 11, 1),
    ));
    final offer = provider.offers.single;
    expect(offer.id, offerId);

    final appId = await provider.applyToOffer(offer: offer, candidateId: 'u1', cvFile: File('/tmp/cv.pdf'));
    expect(provider.myApplications.single.cvUrl, '/app/cv/1.pdf');

    await provider.updateApplicationStatus(appId, ApplicationStatus.accepted);
    await provider.loadMyApplications('u1');
    expect(provider.myApplications.single.status, ApplicationStatus.accepted);
  });
}
