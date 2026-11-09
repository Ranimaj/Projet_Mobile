import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/annonce_model.dart';

/// Base SQLite des Annonces, sur le téléphone : **la seule base** du module
/// (pas de Firebase). Une table `annonces`, une colonne par champ ; les
/// listes (filières et années ciblées) sont stockées en JSON, les dates en
/// millisecondes et les booléens en 0 / 1.
class AnnonceDatabase {
  AnnonceDatabase._(this.db);

  /// Connexion SQLite.
  final Database db;

  static const fileName = 'campusconnect_annonces.db';
  static const table = 'annonces';

  /// À incrémenter à chaque changement de schéma, avec une étape dans `onUpgrade`.
  static const version = 1;

  /// Ouvre (ou crée) la base. [factory] et [path] sont remplaçables dans les
  /// tests (`databaseFactoryFfi`, fichier temporaire ou mémoire).
  static Future<AnnonceDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) => _create(db),
      ),
    );
    return AnnonceDatabase._(db);
  }

  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE $table (
        id             TEXT PRIMARY KEY,
        author_id      TEXT NOT NULL,
        author_name    TEXT NOT NULL,
        title          TEXT NOT NULL,
        content        TEXT NOT NULL,
        category       TEXT NOT NULL,
        is_pinned      INTEGER NOT NULL DEFAULT 0,
        is_urgent      INTEGER NOT NULL DEFAULT 0,
        created_at     INTEGER NOT NULL,
        updated_at     INTEGER,
        comment_count  INTEGER NOT NULL DEFAULT 0,
        send_push      INTEGER NOT NULL DEFAULT 0,
        location_name  TEXT,
        latitude       REAL,
        longitude      REAL,
        target_majors  TEXT NOT NULL DEFAULT '[]',
        target_years   TEXT NOT NULL DEFAULT '[]'
      )''');
    await db.execute('CREATE INDEX idx_annonces_category ON $table(category)');
    await db.execute('CREATE INDEX idx_annonces_author ON $table(author_id)');
    await db.execute('CREATE INDEX idx_annonces_order ON $table(is_pinned DESC, created_at DESC)');
  }

  Future<void> close() => db.close();

  // ---------------------------------------------------------------- lecture

  /// Toutes les annonces : épinglées d'abord, puis les plus récentes.
  Future<List<AnnonceModel>> all() async {
    final rows = await db.query(table, orderBy: 'is_pinned DESC, created_at DESC');
    return [for (final r in rows) fromRow(r)];
  }

  Future<AnnonceModel?> byId(String id) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : fromRow(rows.first);
  }

  // -------------------------------------------------------------- écriture

  /// Insère ou remplace l'annonce [a] sous l'identifiant [id].
  Future<void> upsert(AnnonceModel a, {String? id}) =>
      db.insert(table, toRow(a, id: id), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> remove(String id) => db.delete(table, where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------- conversion

  static Map<String, Object?> toRow(AnnonceModel a, {String? id}) => {
        'id': id ?? a.id,
        'author_id': a.authorId,
        'author_name': a.authorName,
        'title': a.title,
        'content': a.content,
        'category': a.category,
        'is_pinned': a.isPinned ? 1 : 0,
        'is_urgent': a.isUrgent ? 1 : 0,
        'created_at': a.createdAt.millisecondsSinceEpoch,
        'updated_at': a.updatedAt?.millisecondsSinceEpoch,
        'comment_count': a.commentCount,
        'send_push': a.sendPush ? 1 : 0,
        // Un lieu n'a de sens qu'avec ses coordonnées.
        'location_name': a.hasLocation ? a.locationName : null,
        'latitude': a.hasLocation ? a.latitude : null,
        'longitude': a.hasLocation ? a.longitude : null,
        'target_majors': jsonEncode(a.targetMajors),
        'target_years': jsonEncode(a.targetYears),
      };

  static AnnonceModel fromRow(Map<String, Object?> r) {
    List<String> list(String col) {
      try {
        final decoded = jsonDecode(r[col] as String? ?? '[]');
        return decoded is List ? decoded.map((e) => e.toString()).toList() : const [];
      } catch (_) {
        return const [];
      }
    }

    DateTime? date(String col) =>
        r[col] == null ? null : DateTime.fromMillisecondsSinceEpoch((r[col] as num).toInt());

    return AnnonceModel(
      id: r['id'] as String,
      authorId: r['author_id'] as String,
      authorName: r['author_name'] as String,
      title: r['title'] as String,
      content: r['content'] as String,
      category: r['category'] as String,
      isPinned: r['is_pinned'] == 1,
      isUrgent: r['is_urgent'] == 1,
      createdAt: date('created_at')!,
      updatedAt: date('updated_at'),
      commentCount: (r['comment_count'] as num?)?.toInt() ?? 0,
      targetMajors: list('target_majors'),
      targetYears: list('target_years'),
      sendPush: r['send_push'] == 1,
      locationName: r['location_name'] as String?,
      latitude: (r['latitude'] as num?)?.toDouble(),
      longitude: (r['longitude'] as num?)?.toDouble(),
    );
  }
}
