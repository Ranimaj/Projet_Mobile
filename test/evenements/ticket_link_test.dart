import 'package:campusconnect/core/theme/app_colors.dart';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/event_categories.dart';
import 'package:campusconnect/screens/evenements/event_style.dart';
import 'package:campusconnect/screens/evenements/ticket_link.dart';
import 'package:campusconnect/screens/evenements/ticket_rules.dart';
import 'package:campusconnect/screens/evenements/ticket_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adresse du QR du billet (page docs/billet/index.html) et lecture par le
/// scanner de l'organisateur.
void main() {
  const base = TicketRules.billetBaseUrl;
  const eventId = '3b70c2e1-9f4d-4c1a-8a77-5e2f10d4b9aa';
  const uid = '3da7f0b2-1c6e-4e8d-b1f3-7a9c2d5e8f01';
  final start = DateTime.utc(2026, 11, 10, 17, 0);

  EventModel ev({
    String id = eventId,
    String title = 'Atelier photo',
    String category = EventCategories.culture,
    String location = 'Hall principal',
    double? price = 15,
    List<String> registered = const [uid],
    List<String> present = const [],
  }) =>
      EventModel(
        id: id,
        organizerId: 'org',
        organizerName: 'Club',
        title: title,
        description: 'Description',
        category: category,
        startDate: start,
        location: location,
        price: price,
        registeredUserIds: registered,
        checkedInUserIds: present,
      );

  /// Paramètres d'affichage (après le « ? » du fragment), décodés comme le
  /// fait la page (URLSearchParams).
  Map<String, String> params(String link) {
    final fragment = link.substring(link.indexOf('#') + 1);
    return Uri.splitQueryString(fragment.substring(fragment.indexOf('?') + 1));
  }

  group('adresse du billet', () {
    test('forme exacte : base, fragment CC1 encodé, paramètres', () {
      final link = TicketLink.build(ev(), uid, 'Yasmine Ben Salah');
      expect(base, 'https://abdelaziz-belkhiria.github.io/campus-billet/');
      expect(link, startsWith('$base#CC1%7C$eventId%7C$uid?t='));
      expect(params(link), {
        't': 'Atelier photo',
        'n': 'Yasmine Ben Salah',
        'c': 'Culture',
        'k': 'FB923C',
        'd': '2026-11-10T17:00:00Z',
        'e': '2026-11-10T19:00:00Z',
        'p': 'Hall principal',
        'x': '15 TND',
        'r': '3B70-3DA7',
      });
      // Ordre des paramètres de la demande, la référence en dernier.
      expect(params(link).keys.toList(), ['t', 'n', 'c', 'k', 'd', 'e', 'p', 'x', 'r']);
    });

    group('référence « r » : celle affichée sous le QR', () {
      // Expression de docs/billet/index.html pour les identifiants et pour r.
      final pageIds = RegExp(r'^CC1\|([A-Za-z0-9_-]{1,64})\|([A-Za-z0-9_-]{1,64})$');
      final pageRef = RegExp(r'^[0-9A-Z-]{3,20}$');

      for (final (name, eventId, holder, expected) in [
        ('UUID', eventId, uid, '3B70-3DA7'),
        ('démo', 'demo-evt-rentree', 'demo-amel', 'DEMO-DEMO'),
        ('démo courts', 'e1', 'demo_u1', 'E1-DEMO'),
      ]) {
        test('identifiants $name : r présent, identique à l’écran, aller-retour', () {
          final link = TicketLink.build(ev(id: eventId, registered: [holder]), holder, 'Amel');
          final r = params(link)['r'];

          expect(r, expected);
          expect('Billet n° $r', TicketView.reference(eventId, holder));
          expect(r, matches(pageRef));
          expect(link.length, lessThanOrEqualTo(TicketLink.maxLength));

          final ticket = TicketRules.parseTicketPayload(link)!;
          expect((ticket.eventId, ticket.uid), (eventId, holder));
          // La page lit les mêmes identifiants dans le fragment.
          final fragment = link.substring(base.length + 1);
          final idPart = Uri.decodeComponent(fragment.substring(0, fragment.indexOf('?')));
          expect(pageIds.firstMatch(idPart)?.groups([1, 2]), [eventId, holder]);
          // Et le scan donne le même verdict que l'ancien texte.
          final now = start.add(const Duration(minutes: 10));
          final e = ev(id: eventId, registered: [holder]);
          expect(TicketRules.scanVerdict(e, link, now).verdict, ScanVerdict.markPresent);
          expect(TicketRules.scanVerdict(e, TicketRules.buildTicketPayload(eventId, holder), now).verdict,
              ScanVerdict.markPresent);
        });
      }

      test('textes très accentués : ≤ 512, r et l’identifiant gardés', () {
        final accents = 'é' * 200;
        for (final (id, holder) in [(eventId, uid), ('demo-evt-rentree', 'demo-amel')]) {
          final link = TicketLink.build(ev(id: id, title: accents, location: accents, category: accents), holder, accents);
          expect(link.length, lessThanOrEqualTo(TicketLink.maxLength));
          expect(params(link)['r'], TicketLink.referenceCode(id, holder));
          expect(TicketRules.parseTicketPayload(link)?.uid, holder);
        }
      });
    });

    test('aller-retour avec le lecteur du scanner', () {
      for (final id in [eventId, 'evt-123', 'demo_evt']) {
        final link = TicketLink.build(ev(id: id), 'demo-amel', 'Amel');
        final ticket = TicketRules.parseTicketPayload(link)!;
        expect((ticket.eventId, ticket.uid), (id, 'demo-amel'));
      }
    });

    test('textes coupés : titre 60, nom 40, catégorie 24, lieu 60', () {
      final long = 'A' * 100;
      final link = TicketLink.build(ev(title: long, location: long, category: long), uid, long);
      final p = params(link);
      expect(p['t'], '${'A' * 59}…');
      expect(p['n'], '${'A' * 39}…');
      expect(p['c'], '${'A' * 23}…');
      expect(p['p'], '${'A' * 59}…');
      expect(TicketLink.cut('  court  ', 60), 'court');
      expect(TicketLink.cut('x' * 60, 60), 'x' * 60);
    });

    test('accents et caractères spéciaux : encodés, relus à l’identique', () {
      const title = 'Soirée « Jazz & Café » #1 ? 100 % = oui/non + ça';
      const name = 'Zoé N’Diaye-Ben Aïcha';
      const place = 'Salle B&C, 1er étage (côté #est)';
      final link = TicketLink.build(ev(title: title, location: place), uid, name);
      final fragment = link.substring(base.length + 1);
      // Aucun caractère réservé ne sort de son paramètre : un seul « ? », un
      // seul « # » (avant le fragment) et 8 séparateurs « & » (9 paramètres).
      expect('#'.allMatches(link).length, 1);
      expect('?'.allMatches(fragment).length, 1);
      expect('&'.allMatches(fragment).length, 8);
      expect(link, isNot(contains(' ')));
      final p = params(link);
      expect((p['t'], p['n'], p['p']), (title, name, place));
      expect(TicketRules.parseTicketPayload(link)?.uid, uid);
    });

    test('couleur : celle de la catégorie dans l’application (bande du billet)', () {
      for (final category in [...EventCategories.all, 'Inconnue']) {
        final link = TicketLink.build(ev(category: category), uid, 'A');
        expect(params(link)['k'], TicketLink.colorHex(EventStyle.categoryColor(category)), reason: category);
        expect(params(link)['k'], matches(RegExp(r'^[0-9A-F]{6}$')));
      }
      expect(TicketLink.colorHex(AppColors.primary), '4F46E5');
      expect(params(TicketLink.build(ev(category: EventCategories.sport), uid, 'A'))['k'], '10B981');
    });

    test('prix : « Gratuit » ou « N TND »', () {
      expect(params(TicketLink.build(ev(price: null), uid, 'A'))['x'], 'Gratuit');
      expect(params(TicketLink.build(ev(price: 0), uid, 'A'))['x'], 'Gratuit');
      expect(params(TicketLink.build(ev(price: 15), uid, 'A'))['x'], '15 TND');
      expect(params(TicketLink.build(ev(price: 12.5), uid, 'A'))['x'], '12,50 TND');
    });

    test('dates en ISO 8601 UTC, quel que soit le fuseau de l’appareil', () {
      expect(TicketLink.isoUtc(DateTime.utc(2026, 1, 2, 3, 4, 5, 678)), '2026-01-02T03:04:05Z');
      final local = DateTime(2026, 11, 10, 18);
      expect(DateTime.parse(TicketLink.isoUtc(local)), local.toUtc().copyWith(millisecond: 0, microsecond: 0));
    });

    test('longueur totale bornée, même avec des textes très accentués', () {
      final usual = TicketLink.build(
          ev(title: 'Grande soirée de rentrée des clubs et associations du campus', location: 'Esplanade centrale, bâtiment B, ESPRIT Ghazela'),
          uid,
          'Yasmine Ben Salah Trabelsi');
      expect(usual.length, lessThanOrEqualTo(TicketLink.maxLength));
      // Cas courant : rien n'est raccourci au-delà des limites de la page.
      expect(params(usual)['t'], 'Grande soirée de rentrée des clubs et associations du campus');

      final accents = 'é' * 200;
      final worst = TicketLink.build(
          ev(title: accents, location: accents, category: accents, price: 123456.78), uid, accents);
      expect(TicketLink.maxLength, 512);
      expect(worst, startsWith('https://abdelaziz-belkhiria.github.io/campus-billet/#CC1%7C'));
      expect(worst.length, lessThanOrEqualTo(TicketLink.maxLength));
      expect(TicketRules.parseTicketPayload(worst)?.eventId, eventId);
      expect(params(worst)['t'], isNotEmpty);

      // Adresse de base démesurée : les textes partent, l'identifiant reste.
      final hugeBase = 'https://exemple.org/${'b' * 300}/';
      final bare = TicketLink.build(ev(title: accents, location: accents), uid, accents, baseUrl: hugeBase);
      expect(bare.length, lessThanOrEqualTo(TicketLink.maxLength));
      expect(TicketRules.parseTicketPayload(bare, baseUrl: hugeBase)?.uid, uid);
    });
  });

  group('lecture du scanner : deux formes acceptées', () {
    test('ancien texte « CC1|… » et nouvelle adresse', () {
      expect(TicketRules.parseTicketPayload('CC1|evt-123|stud1')?.uid, 'stud1');
      expect(TicketRules.parseTicketPayload('$base#CC1%7Cevt-123%7Cstud1')?.eventId, 'evt-123');
      expect(TicketRules.parseTicketPayload('$base#CC1%7Cevt-123%7Cstud1?t=x&n=y')?.uid, 'stud1');
      // « | » non encodé et retour à la ligne final d'un lecteur : tolérés.
      expect(TicketRules.parseTicketPayload('$base#CC1|evt-123|stud1\n')?.uid, 'stud1');
    });

    test('nouvelle adresse campus-billet et ancienne adresse ranimaj acceptées', () {
      const fresh = 'https://abdelaziz-belkhiria.github.io/campus-billet/';
      const old = 'https://ranimaj.github.io/Projet_Mobile/billet/';
      expect(TicketRules.legacyBilletBaseUrls, [old]);
      for (final b in [fresh, old]) {
        final ticket = TicketRules.parseTicketPayload('$b#CC1%7Cdemo-evt%7Cdemo-amel?t=x&r=DEMO-DEMO');
        expect((ticket?.eventId, ticket?.uid), ('demo-evt', 'demo-amel'), reason: b);
      }
      // Billet généré avec l'ancienne adresse : même verdict qu'avec la nouvelle.
      final now = start.add(const Duration(minutes: 10));
      final link = TicketLink.build(ev(), uid, 'Yasmine');
      final oldLink = TicketLink.build(ev(), uid, 'Yasmine', baseUrl: old);
      expect(oldLink, startsWith('$old#'));
      expect(TicketRules.scanVerdict(ev(), oldLink, now).verdict, ScanVerdict.markPresent);
      expect(TicketRules.scanVerdict(ev(), link, now).verdict, ScanVerdict.markPresent);
    });

    test('autre site ou adresse voisine : refusé', () {
      for (final raw in [
        'http://abdelaziz-belkhiria.github.io/campus-billet/#CC1%7Cevt-123%7Cstud1',
        'https://abdelaziz-belkhiria.github.io/campus-billet.evil.com/#CC1%7Cevt-123%7Cstud1',
        'https://abdelaziz-belkhiria.github.io/campus-billetX#CC1%7Cevt-123%7Cstud1',
        'https://autre.github.io/campus-billet/#CC1%7Cevt-123%7Cstud1',
        'https://abdelaziz-belkhiria.github.io/#CC1%7Cevt-123%7Cstud1',
        'https://exemple.com/billet/#CC1%7Cevt-123%7Cstud1',
        'http://ranimaj.github.io/Projet_Mobile/billet/#CC1%7Cevt-123%7Cstud1',
        'https://ranimaj.github.io/Projet_Mobile/billet.evil.com/#CC1%7Cevt-123%7Cstud1',
        'https://ranimaj.github.io/Projet_Mobile/billetX#CC1%7Cevt-123%7Cstud1',
        '${base}index.html#CC1%7Cevt-123%7Cstud1',
        'https://evil.com/?r=$base#CC1%7Cevt-123%7Cstud1',
        '$base?CC1%7Cevt-123%7Cstud1',
      ]) {
        expect(TicketRules.parseTicketPayload(raw), isNull, reason: raw);
      }
    });

    test('fragment mal formé : refusé', () {
      for (final fragment in [
        '',
        '?t=x',
        'CC1%7Cevt-123',
        'CC2%7Cevt-123%7Cstud1',
        'CC1%7Cevt%20123%7Cstud1',
        'CC1%7Cevt-123%7Cstud1%7Cextra',
        'CC1%7Cevt-123%7C%3Cscript%3E',
        'CC1%7Cevt-123%7Cstud1%0A',
        'CC1%7Cevt-123%7Cstud%E0%A4%A',
        'CC1%7Cevt-123%7Cstud1%',
      ]) {
        expect(TicketRules.parseTicketPayload('$base#$fragment'), isNull, reason: fragment);
      }
    });

    test('verdict : l’adresse donne le même résultat que l’ancien texte', () {
      final now = start.add(const Duration(minutes: 10));
      final link = TicketLink.build(ev(), uid, 'Yasmine');
      final legacy = TicketRules.buildTicketPayload(eventId, uid);
      for (final e in [ev(), ev(present: const [uid]), ev(registered: const []), ev(id: 'autre-evt')]) {
        final a = TicketRules.scanVerdict(e, link, now);
        final b = TicketRules.scanVerdict(e, legacy, now);
        expect((a.verdict, a.uid, a.reason), (b.verdict, b.uid, b.reason));
      }
      expect(TicketRules.scanVerdict(ev(), link, now).verdict, ScanVerdict.markPresent);
      expect(TicketRules.scanVerdict(ev(), link.replaceFirst(base, 'https://exemple.com/billet/'), now).verdict,
          ScanVerdict.invalid);
      expect(TicketRules.scanVerdict(ev(), '$base#CC1%7C$eventId', now).verdict, ScanVerdict.invalid);
    });

    test('adresse de base personnalisée', () {
      const custom = 'https://campus.exemple.tn/billet/';
      final link = TicketLink.build(ev(), uid, 'A', baseUrl: custom);
      expect(link, startsWith('$custom#'));
      expect(TicketRules.parseTicketPayload(link, baseUrl: custom)?.uid, uid);
      expect(TicketRules.parseTicketPayload(link), isNull);
    });
  });
}
