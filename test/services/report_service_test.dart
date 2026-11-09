import 'package:campusconnect/services/report_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ReportService service;
  setUp(() async {
    db = FakeFirebaseFirestore();
    service = ReportService(db);
    await db.collection('users').doc('bob').set({'fullName': 'Bob', 'reportCount': 0});
  });

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
    final doc = await db.collection('reports').doc('amel_bob').get();
    expect(doc['reason'], 'scam');
    expect(doc['details'], 'Demande un virement D17 avant de se voir.');
    expect(doc['status'], 'pending');

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

    expect((await db.collection('users').doc('bob').get())['reportCount'], 1);
    expect(await service.watchPending().first, isEmpty);
    expect((await db.collection('reports').doc('amel_bob').get())['status'], 'confirmed');
    expect((await db.collection('reports').doc('chris_bob').get())['reviewedBy'], 'admin');
  });
}
