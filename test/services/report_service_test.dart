import 'package:campusconnect/services/local_store.dart';
import 'package:campusconnect/services/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/local_db.dart';

void main() {
  late LocalStore store;
  late ReportService service;
  final now = DateTime(2026, 11, 9, 10);

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
    service = ReportService(store: store, clock: () => now);
    await store.set('users', 'bob', {'fullName': 'Bob', 'reportCount': 0});
  });
  tearDown(closeTestDatabase);

  Future<void> report({String reporter = 'amel'}) => service.submit(
        reporterId: reporter,
        reporterName: reporter,
        targetId: 'bob',
        targetName: 'Bob',
        reason: ReportReason.scam,
        details: '  Demande un virement D17 avant de se voir.  ',
        articleId: 'a1',
      );

  test('a report is stored once per reporter and target', () async {
    await report();
    final doc = store.get('reports', 'amel_bob')!;
    expect(doc['reason'], 'scam');
    expect(doc['details'], 'Demande un virement D17 avant de se voir.');
    expect(doc['status'], 'pending');
    expect(parseDate(doc['createdAt']), now);

    await expectLater(report(), throwsA(isA<AlreadyReported>()));
    await report(reporter: 'chris'); // another student can still report
    expect(await service.watchPending().first, hasLength(2));
  });

  test('nobody can report themselves', () {
    expect(
      service.submit(
          reporterId: 'bob', reporterName: 'Bob', targetId: 'bob', targetName: 'Bob', reason: ReportReason.other),
      throwsArgumentError,
    );
  });

  test('confirming increments reportCount; dismissing does not', () async {
    await report();
    await report(reporter: 'chris');
    final pending = await service.watchPending().first;

    await service.confirm(pending.firstWhere((r) => r.reporterId == 'amel'), adminId: 'admin');
    await service.dismiss(pending.firstWhere((r) => r.reporterId == 'chris'), adminId: 'admin');

    expect(store.get('users', 'bob')!['reportCount'], 1);
    expect(await service.watchPending().first, isEmpty);
    expect(store.get('reports', 'amel_bob')!['status'], 'confirmed');
    expect(store.get('reports', 'chris_bob')!['reviewedBy'], 'admin');
  });

  test('confirming the same report twice counts once', () async {
    await report();
    final r = (await service.watchPending().first).single;
    await service.confirm(r, adminId: 'admin');
    await service.confirm(r, adminId: 'admin');
    expect(store.get('users', 'bob')!['reportCount'], 1);
  });

  test('the pending list follows new reports, oldest first', () async {
    final seen = <List<String>>[];
    final sub = service.watchPending().listen((l) => seen.add([for (final r in l) r.reporterId]));
    await pumpEventQueue();
    await report();
    await ReportService(store: store, clock: () => now.add(const Duration(minutes: 1))).submit(
        reporterId: 'chris', reporterName: 'chris', targetId: 'bob', targetName: 'Bob', reason: ReportReason.other);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen.first, isEmpty);
    expect(seen.last, ['amel', 'chris']);
  });
}
