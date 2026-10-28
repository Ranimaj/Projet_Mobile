import 'package:campusconnect/core/utils/activity_stats.dart';
import 'package:campusconnect/models/annonce_model.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dimanche 18 octobre 2026.
final _now = DateTime(2026, 10, 18, 20, 30);

ArticleModel _article(String owner, DateTime at) => ArticleModel(
    id: 'a',
    ownerId: owner,
    ownerName: '',
    title: 't',
    description: '',
    price: 1,
    category: 'c',
    createdAt: at);

AnnonceModel _notice(String author, DateTime at) => AnnonceModel(
    id: 'n',
    authorId: author,
    authorName: '',
    title: 't',
    content: '',
    category: 'c',
    createdAt: at);

EventModel _event(String org, DateTime at) => EventModel(
    id: 'e',
    organizerId: org,
    organizerName: '',
    title: 't',
    description: '',
    category: 'c',
    startDate: at,
    location: '');

ApplicationModel _app(String cand, DateTime at) => ApplicationModel(
    id: 'p',
    jobOfferId: 'o',
    jobTitle: 't',
    companyName: 'c',
    candidateId: cand,
    appliedAt: at);

void main() {
  List<double> values(List<dynamic> pts) =>
      [for (final p in pts) p.value as double];

  test('returns 7 points, oldest first, today last, labelled in French', () {
    final pts = weeklyActivity(
        userId: 'u',
        articles: [],
        notices: [],
        events: [],
        applications: [],
        now: _now);
    expect(pts, hasLength(7));
    expect([for (final p in pts) p.label],
        ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM']);
    expect(values(pts), everyElement(0));
  });

  test('sums the four sources per day', () {
    final today = DateTime(2026, 10, 18, 9);
    final yesterday = DateTime(2026, 10, 17, 23);
    final pts = weeklyActivity(
      userId: 'u',
      articles: [_article('u', today), _article('u', yesterday)],
      notices: [_notice('u', today)],
      events: [_event('u', today)],
      applications: [_app('u', today), _app('u', DateTime(2026, 10, 12))],
      now: _now,
    );
    expect(values(pts), [1, 0, 0, 0, 0, 1, 4]);
  });

  test('ignores other users and days outside the window', () {
    final pts = weeklyActivity(
      userId: 'u',
      articles: [
        _article('other', _now),
        _article('u', DateTime(2026, 10, 11))
      ],
      notices: [_notice('other', _now)],
      events: [_event('other', _now)],
      applications: [_app('other', _now)],
      now: _now,
    );
    expect(values(pts), everyElement(0));
  });
}
