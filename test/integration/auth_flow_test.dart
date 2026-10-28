import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/login_screen.dart';
import 'package:campusconnect/screens/auth/register_screen.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:provider/provider.dart';

import '../helpers/pump_app.dart';

/// Parcours complets écran → provider → service → (faux) Firebase, avec le
/// même routage que `_RootRouter` dans main.dart.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Center(
        child: switch (auth.status) {
          AuthStatus.unknown => const CircularProgressIndicator(),
          AuthStatus.authenticated => Text('HOME:${auth.currentUser?.fullName ?? '?'}'),
          AuthStatus.visitor => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('VISITOR'),
                ElevatedButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('go-login'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text('go-register'),
                ),
              ],
            ),
        },
      ),
    );
  }
}

void main() {
  late MockFirebaseAuth firebaseAuth;
  late FakeFirebaseFirestore firestore;
  late AuthProvider provider;

  Future<void> start(WidgetTester tester, {bool signedIn = false}) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    firebaseAuth = MockFirebaseAuth(signedIn: signedIn, mockUser: MockUser(uid: 'some_uid', email: 'amel@esprit.tn'));
    firestore = FakeFirebaseFirestore();
    provider = AuthProvider(authService: AuthService(auth: firebaseAuth, firestore: firestore));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: provider,
        child: MaterialApp(theme: AppTheme.light, home: const _Root()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>?> profile(String uid) async =>
      (await firestore.collection(AppConstants.usersCollection).doc(uid).get()).data();

  testWidgets('a signed-out user lands on the visitor page', (tester) async {
    await start(tester);
    expect(find.text('VISITOR'), findsOneWidget);
    expect(provider.status, AuthStatus.visitor);
  });

  testWidgets('register → profile stored (normalized) → home with the new name', (tester) async {
    await start(tester);

    await tester.tap(find.text('go-register'));
    await tester.pumpAndSettle();

    await enterField(tester, 0, '  amel   ben salah ');
    await enterField(tester, 1, ' Amel.BenSalah@Esprit.TN ');
    await enterField(tester, 3, 'secret123');
    await enterField(tester, 4, 'secret123');
    await tapText(tester, 'Créer mon compte');
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.text('HOME:Amel Ben Salah'), findsOneWidget);

    final uid = firebaseAuth.currentUser!.uid;
    final stored = await profile(uid);
    expect(stored?['email'], 'amel.bensalah@esprit.tn');
    expect(stored?['fullName'], 'Amel Ben Salah');
    expect(stored?['role'], 'student');
  });

  testWidgets('login with an existing account loads its profile and opens home', (tester) async {
    await start(tester);
    await firestore.collection(AppConstants.usersCollection).doc('some_uid').set({
      'fullName': 'Amel Ben Salah',
      'email': 'amel@esprit.tn',
      'role': 'student',
    });

    await tester.tap(find.text('go-login'));
    await tester.pumpAndSettle();
    await enterField(tester, 0, 'amel@esprit.tn');
    await enterField(tester, 1, 'secret123');
    await tapText(tester, 'Se connecter');
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('HOME:Amel Ben Salah'), findsOneWidget);
  });

  testWidgets('wrong password keeps the user on the login screen with a message', (tester) async {
    await start(tester);
    whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
        .on(firebaseAuth)
        .thenThrow(FirebaseAuthException(code: 'wrong-password'));

    await tester.tap(find.text('go-login'));
    await tester.pumpAndSettle();
    await enterField(tester, 0, 'amel@esprit.tn');
    await enterField(tester, 1, 'nope');
    await tapText(tester, 'Se connecter');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(provider.status, AuthStatus.visitor);
  });

  testWidgets('logout returns to the visitor page', (tester) async {
    await start(tester, signedIn: true);
    expect(provider.status, AuthStatus.authenticated);

    await provider.logout();
    await tester.pumpAndSettle();

    expect(find.text('VISITOR'), findsOneWidget);
    expect(firebaseAuth.currentUser, isNull);
  });

  testWidgets('duplicate email on register shows the error and creates no profile', (tester) async {
    await start(tester);
    whenCalling(Invocation.method(#createUserWithEmailAndPassword, null))
        .on(firebaseAuth)
        .thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

    await tester.tap(find.text('go-register'));
    await tester.pumpAndSettle();
    await enterField(tester, 0, 'Amel Test');
    await enterField(tester, 1, 'amel@esprit.tn');
    await enterField(tester, 3, 'secret123');
    await enterField(tester, 4, 'secret123');
    await tapText(tester, 'Créer mon compte');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Cet email est déjà utilisé.'), findsOneWidget);
    expect(firestore.dump(), isNot(contains('Amel Test')));
  });
}
