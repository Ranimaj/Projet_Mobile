import 'dart:io';

import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/screens/profile/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/authenticated.dart';
import '../helpers/pump_app.dart';

void main() {
  late AuthHarness h;

  setUpAll(() {
    registerFallbackValue(sampleUser);
    registerFallbackValue(File('fallback.jpg'));
  });

  setUp(() {
    h = AuthHarness();
    // Par défaut le service renvoie le profil tel qu'il lui est passé.
    when(() => h.service.updateProfile(any()))
        .thenAnswer((inv) async => inv.positionalArguments.first as AppUser);
  });
  tearDown(() => h.dispose());

  Future<void> open(WidgetTester tester,
      {Future<File?> Function()? pickImage}) async {
    await h.signIn(tester);
    await h.pump(tester, EditProfileScreen(pickImage: pickImage));
  }

  AppUser savedUser() =>
      verify(() => h.service.updateProfile(captureAny())).captured.single
          as AppUser;

  Future<void> pickDepartment(WidgetTester tester, String label) async {
    final dropdown = find.byKey(const Key('department-dropdown'));
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('is prefilled with the current profile', (tester) async {
    await open(tester);

    expect(
        find.widgetWithText(TextFormField, 'Amel Ben Salah'), findsOneWidget);
    expect(
        find.widgetWithText(TextFormField, 'Génie Logiciel'), findsOneWidget);
    expect(find.text('3ème année'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Flutter'), findsOneWidget);
    expect(
        find.text('amel@esprit.tn'), findsOneWidget); // email en lecture seule
  });

  testWidgets('rejects an invalid name without saving', (tester) async {
    await open(tester);

    await enterField(tester, 0, 'A');
    await tapText(tester, 'Enregistrer');
    await tester.pump();

    expect(find.text('Nom trop court'), findsOneWidget);
    verifyNever(() => h.service.updateProfile(any()));
  });

  testWidgets('saves the edited fields and closes', (tester) async {
    await open(tester);

    await enterField(tester, 0, 'amel nouvelle');
    await pickDepartment(tester, 'Business');
    await tester.tap(find.byKey(const Key('year-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2ème année').last);
    await tester.pumpAndSettle();

    await tapText(tester, 'Enregistrer');
    await tester.pumpAndSettle();

    final saved = savedUser();
    expect(saved.fullName,
        'amel nouvelle'); // la normalisation est faite par le service
    expect(saved.major, 'Business');
    expect(saved.year, '2ème année');
    expect(saved.skills, ['Flutter']);
    expect(saved.role, sampleUser.role);
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(find.text('Profil mis à jour.'), findsOneWidget);
  });

  testWidgets('skills can be added (with validation) and removed',
      (tester) async {
    await open(tester);

    await tapText(tester, 'Ajouter');
    await tester.pump();
    expect(find.text('Compétence vide'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('skill-field')), 'flutter');
    await tapText(tester, 'Ajouter');
    await tester.pump();
    expect(find.text('Déjà ajoutée'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('skill-field')), 'Firebase');
    await tapText(tester, 'Ajouter');
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'Firebase'), findsOneWidget);
    expect(find.text('Déjà ajoutée'), findsNothing);

    await tester.tap(find.descendant(
      of: find.widgetWithText(InputChip, 'Flutter'),
      matching: find.byIcon(Icons.close_rounded),
    ));
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'Flutter'), findsNothing);

    await tapText(tester, 'Enregistrer');
    await tester.pumpAndSettle();
    expect(savedUser().skills, ['Firebase']);
  });

  testWidgets('shows the error and stays when saving fails', (tester) async {
    when(() => h.service.updateProfile(any()))
        .thenThrow(AuthFailure.fromCode('network-request-failed'));
    await open(tester);

    await tapText(tester, 'Enregistrer');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Pas de connexion réseau.'), findsOneWidget);
    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  testWidgets('picking a photo uploads it and updates the profile',
      (tester) async {
    final file = File('avatar.jpg');
    when(() => h.storage.uploadAvatar(file, uid: 'uid-1'))
        .thenAnswer((_) async => 'https://cdn/new.jpg');
    await open(tester, pickImage: () async => file);

    await tester.tap(find.byIcon(Icons.photo_camera_rounded));
    await tester.pumpAndSettle();

    verify(() => h.storage.uploadAvatar(file, uid: 'uid-1')).called(1);
    expect(savedUser().photoUrl, 'https://cdn/new.jpg');
    expect(find.text('Photo de profil mise à jour.'), findsOneWidget);
  });

  testWidgets('cancelling the picker does nothing', (tester) async {
    await open(tester, pickImage: () async => null);

    await tester.tap(find.byIcon(Icons.photo_camera_rounded));
    await tester.pumpAndSettle();

    verifyNever(() => h.storage.uploadAvatar(any(), uid: any(named: 'uid')));
    verifyNever(() => h.service.updateProfile(any()));
  });

  testWidgets('an upload failure is reported', (tester) async {
    final file = File('big.jpg');
    when(() => h.storage.uploadAvatar(file, uid: 'uid-1'))
        .thenThrow(AuthFailure.fromCode('invalid-file'));
    await open(tester, pickImage: () async => file);

    await tester.tap(find.byIcon(Icons.photo_camera_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Fichier invalide'), findsOneWidget);
    verifyNever(() => h.service.updateProfile(any()));
  });

  group('department', () {
    testWidgets('dropdown lists the 7 departments', (tester) async {
      await open(tester);
      final dropdown = find.byKey(const Key('department-dropdown'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      for (final d in AppConstants.departments) {
        expect(find.text(d), findsWidgets);
      }
      expect(AppConstants.departments, hasLength(7));
    });

    testWidgets('a custom existing major preselects Autre with the text filled',
        (tester) async {
      await open(tester);
      expect(find.byKey(const Key('department-other')), findsOneWidget);
      expect(
          find.widgetWithText(TextFormField, 'Génie Logiciel'), findsOneWidget);
      expect(find.text('Autre'), findsOneWidget);
    });

    testWidgets('Autre reveals the text field and saves its text as major',
        (tester) async {
      await open(tester);
      await pickDepartment(tester, 'Business');
      expect(find.byKey(const Key('department-other')), findsNothing);

      await pickDepartment(tester, 'Autre');
      final other = find.byKey(const Key('department-other'));
      expect(other, findsOneWidget);
      await tester.enterText(
          find.descendant(of: other, matching: find.byType(TextFormField)),
          'Data Science');

      await tapText(tester, 'Enregistrer');
      await tester.pumpAndSettle();
      expect(savedUser().major, 'Data Science');
    });

    testWidgets('an existing listed major preselects that department', (tester) async {
      await h.signIn(tester, user: sampleUser.copyWith(major: 'Génie Civil'));
      await h.pump(tester, const EditProfileScreen());
      expect(find.text('Génie Civil'), findsOneWidget);
      expect(find.byKey(const Key('department-other')), findsNothing);
    });

    testWidgets('an empty major leaves the dropdown unselected and saves empty', (tester) async {
      await h.signIn(tester, user: sampleUser.copyWith(major: ''));
      await h.pump(tester, const EditProfileScreen());
      expect(find.byKey(const Key('department-other')), findsNothing);
      for (final d in AppConstants.departments) {
        expect(find.text(d), findsNothing);
      }
      await tapText(tester, 'Enregistrer');
      await tester.pumpAndSettle();
      expect(savedUser().major, '');
    });

    testWidgets('switching from Autre to a listed department discards the text', (tester) async {
      await open(tester); // Génie Logiciel -> Autre
      final other = find.descendant(
          of: find.byKey(const Key('department-other')), matching: find.byType(TextFormField));
      await tester.ensureVisible(other);
      await tester.enterText(other, 'Texte obsolète');
      await pickDepartment(tester, 'Business');
      expect(find.byKey(const Key('department-other')), findsNothing);
      await tapText(tester, 'Enregistrer');
      await tester.pumpAndSettle();
      expect(savedUser().major, 'Business');
    });

    testWidgets('invalid free text is rejected inline', (tester) async {
      await open(tester);
      final other = find.descendant(
          of: find.byKey(const Key('department-other')), matching: find.byType(TextFormField));
      await tester.ensureVisible(other);
      await tester.enterText(other, 'X');
      await tapText(tester, 'Enregistrer');
      await tester.pump();
      expect(find.text('Filière trop courte'), findsOneWidget);
      verifyNever(() => h.service.updateProfile(any()));
    });

    testWidgets('Autre with a blank text is rejected', (tester) async {
      await open(tester);
      final other = find.descendant(
          of: find.byKey(const Key('department-other')), matching: find.byType(TextFormField));
      await tester.ensureVisible(other);
      await tester.enterText(other, '  ');
      await tapText(tester, 'Enregistrer');
      await tester.pump();
      expect(
        find.descendant(
            of: find.byKey(const Key('department-other')), matching: find.text('Indique ta filière')),
        findsOneWidget,
      );
      verifyNever(() => h.service.updateProfile(any()));
    });

    testWidgets('a listed department is saved and hides the text field',
        (tester) async {
      await open(tester);
      await pickDepartment(tester, 'Génie Civil');
      expect(find.byKey(const Key('department-other')), findsNothing);

      await tapText(tester, 'Enregistrer');
      await tester.pumpAndSettle();
      expect(savedUser().major, 'Génie Civil');
    });
  });

  group('student id', () {
    Finder idField() => find.descendant(
        of: find.byKey(const Key('student-id')),
        matching: find.byType(TextFormField));

    testWidgets('an invalid id is rejected inline', (tester) async {
      await open(tester);
      await tester.ensureVisible(idField());
      await tester.enterText(idField(), 'ab 1');
      await tapText(tester, 'Enregistrer');
      await tester.pump();
      expect(find.text('Identifiant invalide (6 à 12 caractères)'),
          findsOneWidget);
      verifyNever(() => h.service.updateProfile(any()));
    });

    testWidgets('a valid id is saved trimmed', (tester) async {
      await open(tester);
      await tester.ensureVisible(idField());
      await tester.enterText(idField(), ' 19A12345 ');
      await tapText(tester, 'Enregistrer');
      await tester.pumpAndSettle();
      expect(savedUser().studentId, '19A12345');
    });

    testWidgets('emptying an existing id clears it', (tester) async {
      await h.signIn(tester, user: sampleUser.copyWith(studentId: '19A12345'));
      await h.pump(tester, const EditProfileScreen());
      expect(find.widgetWithText(TextFormField, '19A12345'), findsOneWidget);
      await tester.ensureVisible(idField());
      await tester.enterText(idField(), '');
      await tapText(tester, 'Enregistrer');
      await tester.pumpAndSettle();
      expect(savedUser().studentId, isNull);
    });

    testWidgets('an empty id is saved as null', (tester) async {
      await open(tester);
      await tapText(tester, 'Enregistrer');
      await tester.pumpAndSettle();
      expect(savedUser().studentId, isNull);
    });
  });
}
