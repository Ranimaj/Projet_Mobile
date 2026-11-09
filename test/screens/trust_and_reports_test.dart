import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/screens/admin/admin_reports_screen.dart';
import 'package:campusconnect/screens/stages_emploi/job_detail_screen.dart';
import 'package:campusconnect/screens/vente_don/article_detail_screen.dart';
import 'package:campusconnect/services/ai/fraud_detector.dart';
import 'package:campusconnect/services/report_service.dart';
import 'package:campusconnect/widgets/report_user_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/articles.dart';
import '../helpers/authenticated.dart';
import '../helpers/fraud.dart';
import '../helpers/market.dart';

void main() {
  late AuthHarness h;
  final seller = AppUser(
    id: 'seller-1',
    fullName: 'Sami Trabelsi',
    email: 'sami@esprit.tn',
    createdAt: DateTime(2024, 1, 1),
    isVerifiedStudent: true,
    isPhoneVerified: true,
    twoFactorEnabled: true,
  );
  final bike = article('bike', title: 'Vélo de ville', price: 150, description: 'Vélo en très bon état, avec antivol.');
  final sold = [for (var i = 0; i < 3; i++) article('sold$i', status: ArticleStatus.done)];

  setUpAll(() {
    FraudModel.cached = loadFraudModel();
    return initializeDateFormatting('fr_FR');
  });
  setUp(() => h = AuthHarness());
  tearDown(() => h.dispose());

  testWidgets('the seller card shows the trust badge, counting finished sales', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(FakeArticleRepo([bike, ...sold])),
        ArticleDetailScreen(article: bike, sellerLoader: (_) async => seller));
    await tester.pumpAndSettle();

    // 25 + 15 + 10 + 15 (ancienneté) + 9 (3 ventes) = 74 → Argent
    expect(find.text('Argent · 74'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('trust-badge')));
    await tester.tap(find.byKey(const Key('trust-badge')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trust-details')), findsOneWidget);
    expect(find.text('Confiance Argent'), findsOneWidget);
    expect(find.text('9/15'), findsOneWidget);
  });

  testWidgets('no badge when the seller profile cannot be loaded', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(FakeArticleRepo([bike])),
        ArticleDetailScreen(article: bike, sellerLoader: (_) async => null));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trust-badge')), findsNothing);
    expect(find.byKey(const Key('seller-card')), findsOneWidget);
  });

  testWidgets('the report sheet sends a report once', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = ReportService(db);
    await h.signIn(tester);
    await h.pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showReportUserSheet(context, targetId: 'seller-1', targetName: 'Sami', articleId: 'bike', service: service),
            child: const Text('signaler'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('signaler'));
    await tester.pumpAndSettle();
    expect(find.text('Signaler Sami'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-reason-scam')));
    await tester.enterText(find.byKey(const Key('report-details')), 'Demande un paiement D17.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('report-send')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.text('Signaler Sami'), findsNothing);
    final doc = await tester.runAsync(() => db.collection('reports').doc('uid-1_seller-1').get());
    expect(doc!['reason'], 'scam');

    // Une seconde fois : refus expliqué, la feuille reste ouverte.
    await tester.tap(find.text('signaler'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-reason-other')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('report-send')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.textContaining('déjà signalé'), findsOneWidget);
  });

  testWidgets('a job offer shows its recruiter trust', (tester) async {
    await h.signIn(tester);
    final offer = JobOfferModel(
      id: 'j1',
      recruiterId: 'rec-1',
      companyName: 'Vermeg',
      title: 'Stage Flutter',
      description: 'Stage de 6 mois.',
      type: JobType.stage,
      location: 'Tunis',
      postedAt: DateTime(2026, 11, 1),
    );
    await h.pump(
        tester,
        JobDetailScreen(
            offer: offer,
            recruiterLoader: (_) async => seller.copyWith(fullName: 'Leila RH')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recruiter-trust')), findsOneWidget);
    expect(find.text('Publiée par Leila RH'), findsOneWidget);
  });

  testWidgets('admins confirm or dismiss reports', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = ReportService(db);
    await tester.runAsync(() async {
      await db.collection('users').doc('seller-1').set({'fullName': 'Sami', 'reportCount': 0});
      for (final reporter in ['amel', 'chris']) {
        await service.submit(
            reporterId: reporter,
            reporterName: reporter,
            targetId: 'seller-1',
            targetName: 'Sami',
            reason: ReportReason.scam);
      }
    });
    await h.signIn(tester);
    await h.pump(tester, AdminReportsScreen(service: service));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.text('Sami'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('confirm-amel_seller-1')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dismiss-chris_seller-1')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();

    expect(find.text('Aucun signalement'), findsOneWidget);
    final user = await tester.runAsync(() => db.collection('users').doc('seller-1').get());
    expect(user!['reportCount'], 1);
  });
}
